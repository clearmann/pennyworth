import AppKit

/// The floating search window.
///
/// A nonactivating panel accepts typing without switching the application's
/// menu bar. Focus and Spaces behavior are verified separately on macOS.
final class LauncherPanel: NSPanel {
    override init(contentRect: NSRect, styleMask: NSWindow.StyleMask, backing: NSWindow.BackingStoreType, defer flag: Bool) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isMovableByWindowBackground = true
        hidesOnDeactivate = false
        // Transparent window + rounded vibrancy view inside = Alfred look.
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
    }

    // Borderless windows refuse key status by default; we need it for typing.
    override var canBecomeKey: Bool { true }
}
