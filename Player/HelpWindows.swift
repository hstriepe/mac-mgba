import AppKit
import PDFKit
import WebKit

/// Help › "<Game> Help": the player's help page (`PlayerHelp.html`, in every built game) in its own window,
/// as CapturePlay shows its manual. The page is fitted to the game: the bridge's facts (system, hardware, the
/// user's key bindings, whether there is a manual) go in as `window.gbp` before the page's script runs.
final class HelpWindowController: NSWindowController, WKNavigationDelegate {
    private let webView: WKWebView
    private let session: EmulatorSession
    private let appName: String

    init(session: EmulatorSession, appName: String) {
        self.session = session
        self.appName = appName
        let configuration = WKWebViewConfiguration()
        webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 760, height: 720), configuration: configuration)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 720),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "\(appName) Help"
        window.contentView = webView
        window.contentMinSize = NSSize(width: 480, height: 360)
        window.isReleasedWhenClosed = false
        window.center()
        window.setFrameAutosaveName("HelpWindow")
        super.init(window: window)
        webView.navigationDelegate = self
        load()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Reloads with the current settings (key bindings may have changed since the window was opened).
    func refresh() { load() }

    private func load() {
        guard let page = Bundle.main.url(forResource: "PlayerHelp", withExtension: "html") else {
            webView.loadHTMLString("<p>The help page is missing from this app.</p>", baseURL: nil)
            return
        }
        let controller = webView.configuration.userContentController
        controller.removeAllUserScripts()
        controller.addUserScript(WKUserScript(source: "window.gbp = \(contextJSON());", injectionTime: .atDocumentStart,
                                              forMainFrameOnly: true))
        webView.loadFileURL(page, allowingReadAccessTo: page.deletingLastPathComponent())
    }

    /// What the page needs to fit this game.
    private func contextJSON() -> String {
        let manifest = session.manifest
        let hardware = session.hardware
        func has(_ flag: GBPHardware) -> Bool { hardware & UInt32(flag.rawValue) != 0 }
        let gba = session.platform == Int32(GBP_PLATFORM_GBA.rawValue)
        var keys: [String: String] = [:]
        for button in ConsoleButton.buttons(gba: gba) {
            keys[button.rawValue] = KeyNames.name(InputController.keyCode(for: button, in: session))
        }
        keys["fastForward"] = KeyNames.name(InputController.keyCode(for: HeldHotkey.fastForward, in: session))
        keys["rewind"] = KeyNames.name(InputController.keyCode(for: HeldHotkey.rewind, in: session))
        let context: [String: Any] = [
            "appName": appName,
            "system": manifest.system,
            "systemName": manifest.systemName,
            "gba": gba,
            "lightSensor": has(GBP_HW_LIGHT_SENSOR),
            "rumble": has(GBP_HW_RUMBLE),
            "tilt": has(GBP_HW_TILT) || has(GBP_HW_GYRO),
            "rtc": has(GBP_HW_RTC),
            "manual": manifest.manual != nil,
            "manualSource": manifest.manual?.source ?? "",
            "romName": manifest.romName ?? manifest.romFile,
            "dataFolder": session.dataFolder.path,
            "saveFolder": session.saveFolder.path,
            "stateFolder": session.stateFolder.path,
            "screenshotFolder": session.screenshotFolder.path,
            "romBaseName": session.romBaseName,
            "mgbaVersion": manifest.build?.mgbaVersion ?? "",
            "keys": keys,
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: context, options: [.sortedKeys]),
              let json = String(data: data, encoding: .utf8) else { return "{}" }
        return json
    }

    // Links: web pages open in the browser.
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else { return decisionHandler(.cancel) }
        switch url.scheme {
        case "file", "about":
            decisionHandler(.allow)
        default:
            NSWorkspace.shared.open(url)
            decisionHandler(.cancel)
        }
    }
}

/// Help › "Game Manual": the PDF the builder put in the app, in its own window; it reopens at the last page read.
final class ManualWindowController: NSWindowController, NSWindowDelegate {
    private let pdfView = PDFView()
    private static let pageKey = "ManualPage"

    init?(url: URL, appName: String) {
        guard let document = PDFDocument(url: url) else { return nil }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 720, height: 820),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "\(appName) Manual"
        window.contentMinSize = NSSize(width: 360, height: 360)
        window.isReleasedWhenClosed = false
        window.center()
        window.setFrameAutosaveName("ManualWindow")
        pdfView.document = document
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.displaysPageBreaks = true
        pdfView.backgroundColor = .windowBackgroundColor
        window.contentView = pdfView
        super.init(window: window)
        window.delegate = self
        let saved = UserDefaults.standard.integer(forKey: Self.pageKey)
        if saved > 0, saved < document.pageCount, let page = document.page(at: saved) {
            pdfView.go(to: page)
        }
        NotificationCenter.default.addObserver(self, selector: #selector(pageChanged), name: .PDFViewPageChanged, object: pdfView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    deinit { NotificationCenter.default.removeObserver(self) }

    @objc private func pageChanged(_ notification: Notification) {
        guard let document = pdfView.document, let page = pdfView.currentPage else { return }
        UserDefaults.standard.set(document.index(for: page), forKey: Self.pageKey)
    }
}
