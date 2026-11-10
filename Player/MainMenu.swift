import AppKit

/// The game app's menu bar: mGBA's menus, reduced to what applies to one embedded game.
/// Not here (by design): opening ROMs, recent files, BIOS loading, multiplayer and link, the debugger and
/// memory/tile/sprite viewers, scripting, the updater. Hardware items (solar sensor) only appear for carts that have it.
enum MainMenu {
    static func build(appName: String, session: EmulatorSession, target: AppDelegate) -> NSMenu {
        let main = NSMenu()

        // App
        let app = submenu(main, appName)
        app.addItem(item("About \(appName)", #selector(AppDelegate.showAbout(_:)), target: target))
        app.addItem(.separator())
        app.addItem(item("Settings…", #selector(AppDelegate.showSettings(_:)), ",", target: target))
        app.addItem(.separator())
        app.addItem(item("Hide \(appName)", #selector(NSApplication.hide(_:)), "h"))
        let hideOthers = item("Hide Others", #selector(NSApplication.hideOtherApplications(_:)), "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        app.addItem(hideOthers)
        app.addItem(item("Show All", #selector(NSApplication.unhideAllApplications(_:))))
        app.addItem(.separator())
        app.addItem(item("Quit \(appName)", #selector(NSApplication.terminate(_:)), "q"))

        // File
        let file = submenu(main, "File")
        file.addItem(item("Import Battery Save…", #selector(AppDelegate.importSave(_:)), target: target))
        file.addItem(item("Export Battery Save…", #selector(AppDelegate.exportSave(_:)), target: target))
        file.addItem(item("Show Save in Finder", #selector(AppDelegate.revealSaveFolder(_:)), target: target))
        file.addItem(.separator())
        let load = NSMenu(title: "Load State")
        let save = NSMenu(title: "Save State")
        for slot in 1...9 {
            let key = String(UnicodeScalar(NSF1FunctionKey + slot - 1).map(Character.init) ?? " ")
            let l = item("Slot \(slot)", #selector(AppDelegate.loadStateSlot(_:)), key, target: target)
            l.keyEquivalentModifierMask = []
            l.tag = slot
            load.addItem(l)
            let s = item("Slot \(slot)", #selector(AppDelegate.saveStateSlot(_:)), key, target: target)
            s.keyEquivalentModifierMask = [.shift]
            s.tag = slot
            save.addItem(s)
        }
        file.addItem(parent("Load State", load))
        file.addItem(parent("Save State", save))
        file.addItem(item("Load State from File…", #selector(AppDelegate.loadStateFromFile(_:)), "o", target: target))
        let saveFile = item("Save State to File…", #selector(AppDelegate.saveStateToFile(_:)), "s", target: target)
        saveFile.keyEquivalentModifierMask = [.command, .shift]
        file.addItem(saveFile)
        file.addItem(.separator())
        let shot = item("Take Screenshot", #selector(AppDelegate.takeScreenshot(_:)), String(UnicodeScalar(NSF12FunctionKey).map(Character.init) ?? " "), target: target)
        shot.keyEquivalentModifierMask = []
        file.addItem(shot)
        file.addItem(.separator())
        file.addItem(item("Close", #selector(NSWindow.performClose(_:)), "w"))

        // Emulation
        let emulation = submenu(main, "Emulation")
        emulation.addItem(item("Pause", #selector(AppDelegate.togglePause(_:)), "p", target: target))
        emulation.addItem(item("Next Frame", #selector(AppDelegate.frameAdvance(_:)), "n", target: target))
        emulation.addItem(item("Reset", #selector(AppDelegate.resetGame(_:)), "r", target: target))
        emulation.addItem(.separator())
        let ff = item("Fast Forward", #selector(AppDelegate.toggleFastForward(_:)), "f", target: target)
        ff.keyEquivalentModifierMask = [.command, .shift]
        emulation.addItem(ff)
        let hint = NSMenuItem(title: "Hold Tab to fast-forward, ` to rewind", action: nil, keyEquivalent: "")
        hint.isEnabled = false
        emulation.addItem(hint)
        if session.hardware & UInt32(GBP_HW_LIGHT_SENSOR.rawValue) != 0 {
            emulation.addItem(.separator())
            let solar = NSMenu(title: "Solar Sensor")
            let darker = item("Darker", #selector(AppDelegate.setSolarLevel(_:)), "[", target: target)
            darker.tag = -1
            let brighter = item("Brighter", #selector(AppDelegate.setSolarLevel(_:)), "]", target: target)
            brighter.tag = -2
            solar.addItem(darker)
            solar.addItem(brighter)
            solar.addItem(.separator())
            for level in 0...10 {
                let l = item("Level \(level)", #selector(AppDelegate.setSolarLevel(_:)), target: target)
                l.tag = level
                solar.addItem(l)
            }
            emulation.addItem(parent("Solar Sensor", solar))
        }
        emulation.addItem(.separator())
        let cheats = item("Cheats…", #selector(AppDelegate.showCheats(_:)), "c", target: target)
        cheats.keyEquivalentModifierMask = [.command, .shift]
        emulation.addItem(cheats)

        // View (mGBA's Audio/Video menu)
        let view = submenu(main, "View")
        let sizes = NSMenu(title: "Frame Size")
        for scale in 1...6 {
            let s = item("\(scale)×", #selector(AppDelegate.setFrameSize(_:)), "\(scale)", target: target)
            s.tag = scale
            sizes.addItem(s)
        }
        view.addItem(parent("Frame Size", sizes))
        let actual = item("Actual Size", #selector(AppDelegate.fitToActualSize(_:)), "a", target: target)
        actual.keyEquivalentModifierMask = [.command, .control]
        view.addItem(actual)
        let fullScreen = item("Enter Full Screen", #selector(AppDelegate.toggleGameFullScreen(_:)), "f", target: target)
        fullScreen.keyEquivalentModifierMask = [.command, .control]
        view.addItem(fullScreen)
        view.addItem(item("Borderless Window", #selector(AppDelegate.toggleBorderless(_:)), "b", target: target))
        view.addItem(.separator())
        let aspect = option("Lock Aspect Ratio", "lockAspectRatio", target)
        aspect.keyEquivalent = "a"
        view.addItem(aspect)
        view.addItem(option("Force Integer Scaling", "lockIntegerScaling", target))
        view.addItem(option("Interframe Blending", "interframeBlending", target))
        view.addItem(option("Bilinear Filtering", "resampleVideo", target))
        if session.platform == Int32(GBP_PLATFORM_GB.rawValue) {
            view.addItem(option("Super Game Boy Borders", "sgb.borders", target))
        }
        view.addItem(.separator())
        let mute = option("Mute", "mute", target)
        mute.keyEquivalent = "m"
        mute.keyEquivalentModifierMask = [.command, .shift]
        view.addItem(mute)

        // Window
        let window = submenu(main, "Window")
        window.addItem(item("Minimize", #selector(NSWindow.performMiniaturize(_:)), "m"))
        window.addItem(item("Zoom", #selector(NSWindow.performZoom(_:))))
        NSApp.windowsMenu = window

        // Help
        let help = submenu(main, "Help")
        help.addItem(item("mGBA Website", #selector(NSWorkspace.openMGBAWebsite(_:)), target: NSWorkspace.shared))
        NSApp.helpMenu = help

        return main
    }

    private static func submenu(_ main: NSMenu, _ title: String) -> NSMenu {
        let menu = NSMenu(title: title)
        main.addItem(parent(title, menu))
        return menu
    }

    private static func parent(_ title: String, _ menu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = menu
        return item
    }

    private static func item(_ title: String, _ action: Selector?, _ key: String = "", target: AnyObject? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = target
        return item
    }

    private static func option(_ title: String, _ key: String, _ target: AppDelegate) -> NSMenuItem {
        let item = item(title, #selector(AppDelegate.toggleConfigOption(_:)), target: target)
        item.representedObject = key
        return item
    }
}

extension NSWorkspace {
    @objc func openMGBAWebsite(_ sender: Any?) {
        if let url = URL(string: "https://mgba.io") { open(url) }
    }
}
