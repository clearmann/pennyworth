import AppKit
import Carbon

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var panel: LauncherPanel?
    private var viewController: LauncherViewController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let viewController = LauncherViewController(items: AppScanner.scanInstalledApplications())
        let panel = LauncherPanel(
            contentRect: NSRect(origin: .zero, size: LauncherViewController.panelSize),
            styleMask: [],
            backing: .buffered,
            defer: false
        )
        panel.contentViewController = viewController
        panel.delegate = self
        viewController.onDismiss = { [weak panel] in panel?.orderOut(nil) }

        self.panel = panel
        self.viewController = viewController

        HotKeyManager.shared.onHotKey = { [weak self] in self?.togglePanel() }
        registerHotKeyWithFallback()
    }

    private func registerHotKeyWithFallback() {
        do {
            try HotKeyManager.shared.register()
        } catch {
            do {
                try HotKeyManager.shared.register(
                    keyCode: UInt32(kVK_Space),
                    modifiers: UInt32(optionKey | shiftKey)
                )
            } catch {
                presentHotKeyConflictAlert()
            }
        }
    }

    private func presentHotKeyConflictAlert() {
        let alert = NSAlert()
        alert.messageText = "Pennyworth 热键被占用"
        alert.informativeText = "⌥Space 和 ⌥⇧Space 都被其他应用抢注了。退出冲突的应用后重启 Pennyworth 即可。"
        alert.alertStyle = .warning
        alert.runModal()
    }

    private func togglePanel() {
        guard let panel else { return }
        if panel.isVisible {
            panel.orderOut(nil)
        } else {
            showPanel()
        }
    }

    private func showPanel() {
        guard let panel, let screen = activeScreen() else { return }
        let size = LauncherViewController.panelSize
        let origin = NSPoint(
            x: screen.visibleFrame.midX - size.width / 2,
            y: screen.visibleFrame.midY - size.height / 2 + 120
        )
        panel.setFrame(NSRect(origin: origin, size: size), display: false)
        panel.makeKeyAndOrderFront(nil)
        viewController?.focusSearchField()
        if #available(macOS 14.0, *) {
            NSApp.activate()
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private func activeScreen() -> NSScreen? {
        let mouseLocation = NSEvent.mouseLocation
        return NSScreen.screens.first(where: { NSMouseInRect(mouseLocation, $0.frame, false) })
            ?? NSScreen.main
    }
}

extension AppDelegate: NSWindowDelegate {
    func windowDidResignKey(_ notification: Notification) {
        panel?.orderOut(nil)
    }
}
