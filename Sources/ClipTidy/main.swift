import AppKit

// Menu bar only: no Dock icon, no main window.
let app = NSApplication.shared
let controller = AppController()
app.delegate = controller
app.setActivationPolicy(.accessory)
app.run()
