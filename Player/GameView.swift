import AppKit
import QuartzCore

/// Shows the emulator's frames, keeps the picture's aspect ratio or integer scale, and passes keys to the input controller.
final class GameView: NSView {
    weak var session: EmulatorSession?
    var input: InputController?
    private let screen = CALayer()
    private var lastSequence = -1
    private var displayLink: CADisplayLink?
    /// Native picture size (240×160 for GBA, 160×144 for GB, 256×224 with Super Game Boy borders).
    /// Set from the platform before the first frame; then follows the frames.
    var nativeSize = CGSize(width: 240, height: 160) { didSet { needsLayout = true } }

    enum MouseEvent {
        case entered, exited, moved(NSPoint)
    }

    /// Mouse movement over the picture (title bar and pointer hiding in `GameWindowController`).
    var onMouse: ((MouseEvent) -> Void)?
    /// The native size changed (for example Super Game Boy borders switched on or off).
    var onNativeSizeChange: (() -> Void)?

    var lockAspectRatio = true { didSet { needsLayout = true } }
    var integerScaling = false { didSet { needsLayout = true } }
    var bilinear = false {
        didSet { screen.magnificationFilter = bilinear ? .linear : .nearest }
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        screen.magnificationFilter = .nearest
        screen.minificationFilter = .linear
        screen.contentsGravity = .resize
        screen.actions = ["contents": NSNull(), "bounds": NSNull(), "position": NSNull()]
        layer?.addSublayer(screen)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var acceptsFirstResponder: Bool { true }
    override var isOpaque: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        displayLink?.invalidate()
        displayLink = nil
        guard window != nil else { return }
        let link = displayLink(target: self, selector: #selector(tick))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    func stopDisplay() {
        displayLink?.invalidate()
        displayLink = nil
    }

    @objc private func tick(_ link: CADisplayLink) {
        guard let session, let image = session.frames.image(after: &lastSequence) else { return }
        let size = CGSize(width: image.width, height: image.height)
        if size != nativeSize {
            nativeSize = size
            onNativeSizeChange?()
        }
        screen.contents = image
    }

    override func layout() {
        super.layout()
        let bounds = self.bounds
        var rect = bounds
        if lockAspectRatio || integerScaling {
            var scale = min(bounds.width / nativeSize.width, bounds.height / nativeSize.height)
            if integerScaling { scale = max(1, floor(scale)) }
            let size = CGSize(width: nativeSize.width * scale, height: nativeSize.height * scale)
            rect = CGRect(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2,
                          width: size.width, height: size.height)
        }
        screen.frame = rect.integral
        screen.contentsScale = window?.backingScaleFactor ?? 2
    }

    // MARK: Mouse

    /// Dragging the picture moves the window (as in QuickTime; the only way to move a borderless one).
    override var mouseDownCanMoveWindow: Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach { removeTrackingArea($0) }
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .mouseMoved, .activeInKeyWindow, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    override func mouseEntered(with event: NSEvent) { onMouse?(.entered) }
    override func mouseExited(with event: NSEvent) { onMouse?(.exited) }
    override func mouseMoved(with event: NSEvent) { onMouse?(.moved(convert(event.locationInWindow, from: nil))) }

    // MARK: Keys

    override func keyDown(with event: NSEvent) {
        if input?.keyDown(event) == true { return }
        // Escape leaves full screen (unless it is bound to a game key, handled above).
        if event.keyCode == 53, let window, window.styleMask.contains(.fullScreen) {
            window.toggleFullScreen(nil)
            return
        }
        super.keyDown(with: event)
    }

    override func keyUp(with event: NSEvent) {
        if input?.keyUp(event) != true { super.keyUp(with: event) }
    }

    override func flagsChanged(with event: NSEvent) {
        input?.flagsChanged(event)
    }
}
