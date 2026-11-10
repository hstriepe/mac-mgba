import AppKit

// The menu bar is built in code (MainMenu.swift), so the app starts without a storyboard or nib.
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
