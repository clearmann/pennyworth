import AppKit

let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
// .accessory = no Dock icon, no menu bar — a background agent, like Alfred.
application.setActivationPolicy(.accessory)
application.run()
