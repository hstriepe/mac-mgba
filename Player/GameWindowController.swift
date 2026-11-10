import AppKit

/// A borderless window still has to take keys: the game is played from the keyboard.
final class GameWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// The game window as a media window, after CapturePlay's `CPWindowManager`:
/// - a QuickTime-style title bar over the picture that shows when the mouse is in the top strip and hides 2 s later
/// - borderless mode (floats above other windows, dragged anywhere)
/// - the window held to the screen's aspect ratio
/// - full screen with the pointer hidden and a latency-critical activity ("game mode")
/// - the display kept awake while the game runs (a controller does not count as user activity)
final class GameWindowController: NSObject {
    /// Player keys in the game's config.ini (not mGBA's).
    static let borderlessKey = "gbplayer.borderless"
    static let preventDisplaySleepKey = "gbplayer.preventDisplaySleep"

    let window: GameWindow
    let view: GameView
    private let session: EmulatorSession
    private let titledMask: NSWindow.StyleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
    private let titleStripHeight: CGFloat = 28
    private var aspectLocked: Bool?
    private var gameActivity: NSObjectProtocol?
    private var sleepActivity: NSObjectProtocol?
    private var sleepTimer: Timer?

    init(session: EmulatorSession, view: GameView, title: String, contentSize: CGSize) {
        self.session = session
        self.view = view
        window = GameWindow(contentRect: NSRect(origin: .zero, size: contentSize), styleMask: titledMask,
                            backing: .buffered, defer: false)
        super.init()
        window.title = title
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = .black
        window.isMovableByWindowBackground = true
        window.collectionBehavior = [.fullScreenPrimary]
        window.isReleasedWhenClosed = false
        window.contentView = view
        configureTitleBar()

        view.onMouse = { [weak self] event in self?.mouse(event) }
        view.onNativeSizeChange = { [weak self] in self?.applyAspectRatio(resize: true) }

        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(willEnterFullScreen), name: NSWindow.willEnterFullScreenNotification, object: window)
        center.addObserver(self, selector: #selector(didEnterFullScreen), name: NSWindow.didEnterFullScreenNotification, object: window)
        center.addObserver(self, selector: #selector(didExitFullScreen), name: NSWindow.didExitFullScreenNotification, object: window)

        let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in self?.updateDisplaySleep() }
        RunLoop.main.add(timer, forMode: .common)
        sleepTimer = timer
    }

    deinit {
        NSObject.cancelPreviousPerformRequests(withTarget: self)
        NotificationCenter.default.removeObserver(self)
    }

    var isFullScreen: Bool { window.styleMask.contains(.fullScreen) }
    var isBorderless: Bool { !window.styleMask.contains(.titled) }

    /// Applies the window settings from the config (at launch, and after a menu or Settings change).
    func applySettings() {
        let borderless = session.configBool(Self.borderlessKey)
        if borderless != isBorderless && !isFullScreen { setBorderless(borderless) }
        let locked = session.configBool("lockAspectRatio")
        if locked != aspectLocked { applyAspectRatio(resize: true) }
        updateDisplaySleep()
    }

    func stop() {
        sleepTimer?.invalidate()
        sleepTimer = nil
        endActivity(&sleepActivity)
        endActivity(&gameActivity)
    }

    // MARK: Title bar

    private func configureTitleBar() {
        window.titlebarAppearsTransparent = true
        setTitleBar(visible: false)
    }

    private func setTitleBar(visible: Bool) {
        NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(hideTitleBar), object: nil)
        window.titleVisibility = visible ? .visible : .hidden
        for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            window.standardWindowButton(button)?.isHidden = !visible
        }
    }

    @objc private func hideTitleBar() {
        guard !isFullScreen else { return }
        setTitleBar(visible: false)
    }

    private func hideTitleBarSoon() {
        NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(hideTitleBar), object: nil)
        perform(#selector(hideTitleBar), with: nil, afterDelay: 2)
    }

    private func mouse(_ event: GameView.MouseEvent) {
        if isFullScreen {
            if case .exited = event { return }
            hidePointerSoon()
            return
        }
        guard !isBorderless else { return }
        switch event {
        case .entered:
            setTitleBar(visible: true)
            hideTitleBarSoon()
        case .exited:
            hideTitleBarSoon()
        case .moved(let point):
            if point.y > view.bounds.height - titleStripHeight {
                setTitleBar(visible: true)
            } else if window.titleVisibility == .visible {
                hideTitleBarSoon()
            }
        }
    }

    // MARK: Borderless

    func toggleBorderless() {
        guard !isFullScreen else { return }
        session.setConfig(Self.borderlessKey, !isBorderless)
        applySettings()
    }

    private func setBorderless(_ borderless: Bool) {
        let content = window.contentRect(forFrameRect: window.frame)
        if borderless {
            window.styleMask = [.borderless, .resizable]
            window.level = .floating
            window.hasShadow = true
        } else {
            window.styleMask = titledMask
            window.level = .normal
            configureTitleBar()
        }
        window.setFrame(window.frameRect(forContentRect: content), display: true)
        window.makeFirstResponder(view)
        aspectLocked = nil
        applyAspectRatio(resize: false)
    }

    // MARK: Aspect ratio and size

    /// Holds the window to the picture's shape when Lock Aspect Ratio is on; `resize` also fits the window now,
    /// keeping its width and top edge.
    func applyAspectRatio(resize: Bool) {
        let native = view.nativeSize
        let locked = session.configBool("lockAspectRatio")
        aspectLocked = locked
        guard locked, native.width > 0, native.height > 0 else {
            window.contentResizeIncrements = NSSize(width: 1, height: 1)
            return
        }
        window.contentAspectRatio = native
        guard resize, !isFullScreen else { return }
        var content = window.contentRect(forFrameRect: window.frame)
        let height = (content.width * native.height / native.width).rounded()
        content.origin.y += content.height - height
        content.size.height = height
        window.setFrame(window.frameRect(forContentRect: content), display: true, animate: false)
    }

    /// Sets the picture to `scale` times its native size (leaving full screen first).
    func setScale(_ scale: Int) {
        if isFullScreen { window.toggleFullScreen(nil) }
        let native = view.nativeSize
        var content = window.contentRect(forFrameRect: window.frame)
        let size = CGSize(width: native.width * CGFloat(scale), height: native.height * CGFloat(scale))
        content.origin.y += content.height - size.height
        content.size = size
        window.setFrame(window.frameRect(forContentRect: content), display: true)
    }

    // MARK: Full screen

    func toggleFullScreen() {
        if isBorderless {
            // Full screen needs a titled window; borderless mode is turned off, as in CapturePlay.
            session.setConfig(Self.borderlessKey, false)
            setBorderless(false)
        }
        window.toggleFullScreen(nil)
    }

    @objc private func willEnterFullScreen(_ notification: Notification) {
        // Full screen shows the system title bar with the menu bar; its buttons must be there.
        setTitleBar(visible: true)
        if gameActivity == nil {
            gameActivity = ProcessInfo.processInfo.beginActivity(options: [.userInitiated, .latencyCritical],
                                                                 reason: "Playing a game in full screen")
        }
    }

    @objc private func didEnterFullScreen(_ notification: Notification) {
        hidePointer()
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(view)
    }

    @objc private func didExitFullScreen(_ notification: Notification) {
        NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(hidePointer), object: nil)
        endActivity(&gameActivity)
        setTitleBar(visible: false)
        applyAspectRatio(resize: true)
    }

    /// Hides the pointer until the mouse moves; it hides again 2 s after the mouse stops.
    @objc private func hidePointer() {
        guard isFullScreen else { return }
        NSCursor.setHiddenUntilMouseMoves(true)
    }

    private func hidePointerSoon() {
        NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(hidePointer), object: nil)
        perform(#selector(hidePointer), with: nil, afterDelay: 2)
    }

    // MARK: Display sleep

    private func updateDisplaySleep() {
        let playing = session.configBool(Self.preventDisplaySleepKey) && !session.isPaused
            && window.isVisible && !window.isMiniaturized && !NSApp.isHidden
        if playing, sleepActivity == nil {
            sleepActivity = ProcessInfo.processInfo.beginActivity(options: [.idleDisplaySleepDisabled, .idleSystemSleepDisabled],
                                                                  reason: "Playing a game")
        } else if !playing {
            endActivity(&sleepActivity)
        }
    }

    private func endActivity(_ activity: inout NSObjectProtocol?) {
        if let current = activity {
            ProcessInfo.processInfo.endActivity(current)
            activity = nil
        }
    }
}
