import AppKit

/// Full-screen frozen-display panel for the screenshot session.
/// Deliberately separate from LauncherPanel: higher level, no auto-hide on focus loss.
final class ScreenshotOverlayPanel: NSPanel {
    override init(contentRect: NSRect, styleMask: NSWindow.StyleMask, backing: NSWindow.BackingStoreType, defer flag: Bool) {
        super.init(contentRect: contentRect, styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        hidesOnDeactivate = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        acceptsMouseMovedEvents = true
    }

    override var canBecomeKey: Bool { true }
}
