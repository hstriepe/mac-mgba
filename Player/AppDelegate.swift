import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// The player: one window, one game. In a built app the game comes from `Contents/Resources/Game/`;
/// the bare template (no game inside) asks for a ROM, for testing.
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSMenuItemValidation {
    private var windowController: GameWindowController?
    private var window: NSWindow? { windowController?.window }
    private var gameView: GameView?
    private(set) var session: EmulatorSession?
    private var input: InputController?
    private var settingsWindow: NSWindow?
    private var cheatsWindow: NSWindow?
    private var helpWindow: HelpWindowController?
    private var manualWindow: ManualWindowController?
    private var pausedByFocus = false

    var appName: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "GB Player"
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            guard let (manifest, rom, bios) = try locateGame() else {
                NSApp.terminate(nil)
                return
            }
            let session = try EmulatorSession(manifest: manifest, romURL: rom, biosFolder: bios,
                                              dataFolder: GamePaths.dataFolder(manifest.dataFolder))
            try session.start()
            self.session = session
            input = InputController(session: session)
            NSApp.mainMenu = MainMenu.build(appName: appName, session: session, target: self)
            makeWindow(session: session)
        } catch {
            let alert = NSAlert(error: error)
            alert.runModal()
            NSApp.terminate(nil)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationWillTerminate(_ notification: Notification) {
        gameView?.stopDisplay()
        windowController?.stop()
        session?.saveCheats()
        session?.stop()
    }

    func applicationDidResignActive(_ notification: Notification) {
        input?.releaseAll()
        guard let session, session.configBool("pauseOnFocusLost"), !session.isPaused else { return }
        session.isPaused = true
        pausedByFocus = true
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        if pausedByFocus {
            session?.isPaused = false
            pausedByFocus = false
        }
    }

    // MARK: Game location

    /// Returns the embedded game, or asks for a ROM when this is the bare template.
    private func locateGame() throws -> (GameManifest, URL, URL?)? {
        let bundle = Bundle.main
        if let manifestURL = bundle.url(forResource: "game", withExtension: "json", subdirectory: "Game") {
            let manifest = try JSONDecoder().decode(GameManifest.self, from: Data(contentsOf: manifestURL))
            let rom = manifestURL.deletingLastPathComponent().appendingPathComponent(manifest.romFile)
            let bios = bundle.resourceURL?.appendingPathComponent("BIOS", isDirectory: true)
            return (manifest, rom, bios)
        }
        // Template without a game: pick a ROM (the template is only run like this while developing).
        let panel = NSOpenPanel()
        panel.title = "Open a Game Boy or Game Boy Advance ROM"
        panel.allowedContentTypes = ["gb", "gbc", "gba", "sgb"].compactMap { UTType(filenameExtension: $0) }
        guard panel.runModal() == .OK, let rom = panel.url else { return nil }
        let ext = rom.pathExtension.lowercased()
        let system = ext == "gba" ? "gba" : (ext == "gbc" ? "gbc" : "gb")
        let name = rom.deletingPathExtension().lastPathComponent
        let bios = ProcessInfo.processInfo.environment["GBPLAYER_BIOS"].map { URL(fileURLWithPath: $0, isDirectory: true) }
        let biosFiles = system == "gba" ? ["gba.bios": "gba_bios.bin"]
            : ["gb.bios": "gb_bios.bin", "gbc.bios": "gbc_bios.bin", "sgb.bios": "sgb_bios.bin"]
        let manifest = GameManifest(title: name, system: system, romFile: rom.lastPathComponent, bios: bios == nil ? [:] : biosFiles,
                                    dataFolder: "Template - " + GamePaths.sanitize(name))
        return (manifest, rom, bios)
    }

    // MARK: Window

    private func makeWindow(session: EmulatorSession) {
        let view = GameView(frame: .zero)
        view.session = session
        view.input = input
        gameView = view

        let native = session.platform == Int32(GBP_PLATFORM_GBA.rawValue) ? CGSize(width: 240, height: 160) : CGSize(width: 160, height: 144)
        view.nativeSize = native
        let scale = CGFloat(session.configInt("videoScale") ?? 3)
        let controller = GameWindowController(session: session, view: view, title: appName,
                                              contentSize: CGSize(width: native.width * scale, height: native.height * scale))
        let window = controller.window
        window.contentMinSize = native
        window.delegate = self
        window.center()
        window.setFrameAutosaveName("GameWindow")
        windowController = controller
        applyVideoSettings()
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(view)
    }

    func applyVideoSettings() {
        guard let session, let view = gameView else { return }
        view.lockAspectRatio = session.configBool("lockAspectRatio")
        view.integerScaling = session.configBool("lockIntegerScaling")
        view.bilinear = session.configBool("resampleVideo")
        windowController?.applySettings()
    }

    func windowDidMiniaturize(_ notification: Notification) {
        input?.releaseAll()
    }

    // MARK: Menu actions

    @objc func togglePause(_ sender: Any?) { session?.isPaused.toggle() }
    @objc func frameAdvance(_ sender: Any?) { session?.frameAdvance() }
    @objc func resetGame(_ sender: Any?) { session?.reset() }
    @objc func toggleFastForward(_ sender: Any?) { session?.fastForwardToggle.toggle() }

    @objc func saveStateSlot(_ sender: NSMenuItem) {
        if session?.saveState(slot: sender.tag) != true { showError("The state could not be saved.") }
    }

    @objc func loadStateSlot(_ sender: NSMenuItem) {
        if session?.loadState(slot: sender.tag) != true { showError("There is no state in slot \(sender.tag).") }
    }

    @objc func saveStateToFile(_ sender: Any?) {
        guard let session else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = session.romBaseName + ".ss0"
        panel.directoryURL = session.stateFolder
        guard panel.runModal() == .OK, let url = panel.url else { return }
        if !session.saveState(to: url) { showError("The state could not be saved.") }
    }

    @objc func loadStateFromFile(_ sender: Any?) {
        guard let session else { return }
        let panel = NSOpenPanel()
        panel.directoryURL = session.stateFolder
        guard panel.runModal() == .OK, let url = panel.url else { return }
        if !session.loadState(from: url) { showError("This file is not a state of this game.") }
    }

    @objc func importSave(_ sender: Any?) {
        guard let session else { return }
        let panel = NSOpenPanel()
        panel.title = "Import a battery save (.sav)"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let alert = NSAlert()
        alert.messageText = "Replace the game's save with “\(url.lastPathComponent)”?"
        alert.informativeText = "The current save is overwritten. The game resets afterwards."
        alert.addButton(withTitle: "Replace")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        if session.importSave(from: url) { session.reset() } else { showError("The save could not be imported.") }
    }

    @objc func exportSave(_ sender: Any?) {
        guard let session else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = session.romBaseName + ".sav"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        if !session.exportSave(to: url) { showError("This game has no battery save to export.") }
    }

    @objc func revealSaveFolder(_ sender: Any?) {
        guard let session else { return }
        let file = session.saveFile
        if FileManager.default.fileExists(atPath: file.path) {
            NSWorkspace.shared.activateFileViewerSelecting([file])
        } else {
            NSWorkspace.shared.open(session.saveFolder)
        }
    }

    @objc func takeScreenshot(_ sender: Any?) {
        guard session?.takeScreenshot() != nil else {
            showError("The screenshot could not be written.")
            return
        }
        NSSound(named: "Grab")?.play()
    }

    @objc func setFrameSize(_ sender: NSMenuItem) {
        session?.setConfig("videoScale", String(sender.tag))
        windowController?.setScale(sender.tag)
    }

    /// CapturePlay's "Fit to Actual Size": the 1× frame size.
    @objc func fitToActualSize(_ sender: Any?) {
        session?.setConfig("videoScale", "1")
        windowController?.setScale(1)
    }

    @objc func toggleBorderless(_ sender: Any?) { windowController?.toggleBorderless() }
    @objc func toggleGameFullScreen(_ sender: Any?) { windowController?.toggleFullScreen() }

    @objc func toggleConfigOption(_ sender: NSMenuItem) {
        guard let session, let key = sender.representedObject as? String else { return }
        session.setConfig(key, !session.configBool(key))
        applyVideoSettings()
    }

    @objc func setSolarLevel(_ sender: NSMenuItem) {
        guard let session else { return }
        var level = Int(session.withCore { gbp_light_level($0) })
        switch sender.tag {
        case -1: level -= 1
        case -2: level += 1
        default: level = sender.tag
        }
        level = min(max(level, 0), 10)
        session.withCore { gbp_set_light_level($0, Int32(level)) }
        session.setConfig("solarLevel", String(level))
    }

    @objc func showSettings(_ sender: Any?) {
        guard let session else { return }
        if settingsWindow == nil {
            let view = SettingsView(model: SettingsModel(session: session, delegate: self))
            let window = NSWindow(contentViewController: NSHostingController(rootView: view))
            window.title = "\(appName) Settings"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            settingsWindow = window
        }
        settingsWindow?.center()
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    @objc func showCheats(_ sender: Any?) {
        guard let session else { return }
        if cheatsWindow == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: CheatsView(model: CheatsModel(session: session))))
            window.title = "Cheats"
            window.styleMask = [.titled, .closable, .resizable]
            window.isReleasedWhenClosed = false
            cheatsWindow = window
        }
        cheatsWindow?.center()
        cheatsWindow?.makeKeyAndOrderFront(nil)
    }

    @objc func showHelp(_ sender: Any?) {
        guard let session else { return }
        if let helpWindow {
            helpWindow.refresh()
        } else {
            helpWindow = HelpWindowController(session: session, appName: appName)
        }
        helpWindow?.showWindow(nil)
    }

    /// The manual the builder put in the app (`Resources/Game/Manual.pdf`).
    @objc func showManual(_ sender: Any?) {
        guard let session, let manual = session.manifest.manual,
              let url = Bundle.main.url(forResource: "Game", withExtension: nil)?.appendingPathComponent(manual.file)
        else { return }
        if manualWindow == nil {
            guard let controller = ManualWindowController(url: url, appName: appName) else {
                showError("The manual could not be opened.")
                return
            }
            manualWindow = controller
        }
        manualWindow?.showWindow(nil)
    }

    @objc func showAbout(_ sender: Any?) {
        guard let session else { return }
        let manifest = session.manifest
        var lines = ["\(manifest.systemName)"]
        if let romName = manifest.romName { lines.append(romName) }
        if let code = manifest.gameCode, !code.isEmpty { lines.append("Game code \(code)") }
        if let crc = manifest.crc32 { lines.append("CRC32 \(crc)") }
        lines.append("")
        lines.append("Emulation by mGBA \(manifest.build?.mgbaVersion ?? "") © Jeffrey Pfau and contributors, Mozilla Public License 2.0 (mgba.io).")
        if let build = manifest.build { lines.append("Built with GB App Builder \(build.builderVersion) on \(build.date).") }
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: appName,
            .credits: NSAttributedString(string: lines.joined(separator: "\n"),
                                         attributes: [.font: NSFont.systemFont(ofSize: 11)]),
        ])
    }

    /// Input for the Controls settings.
    var inputController: InputController? { input }

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        guard let session else { return false }
        switch item.action {
        case #selector(togglePause(_:)):
            item.state = session.isPaused ? .on : .off
        case #selector(toggleFastForward(_:)):
            item.state = session.fastForwardToggle ? .on : .off
        case #selector(toggleConfigOption(_:)):
            if let key = item.representedObject as? String { item.state = session.configBool(key) ? .on : .off }
        case #selector(toggleBorderless(_:)):
            item.state = windowController?.isBorderless == true ? .on : .off
            return windowController?.isFullScreen != true
        case #selector(toggleGameFullScreen(_:)):
            item.title = windowController?.isFullScreen == true ? "Exit Full Screen" : "Enter Full Screen"
        case #selector(setFrameSize(_:)):
            item.state = (session.configInt("videoScale") ?? 3) == item.tag ? .on : .off
        case #selector(setSolarLevel(_:)):
            if item.tag >= 0 { item.state = Int(session.withCore { gbp_light_level($0) }) == item.tag ? .on : .off }
        case #selector(loadStateSlot(_:)):
            return FileManager.default.fileExists(atPath: session.stateFile(slot: item.tag).path)
        default:
            break
        }
        return true
    }

    func showError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = message
        alert.runModal()
    }
}
