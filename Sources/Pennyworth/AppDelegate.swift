import AppKit
import Carbon

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let settings = SettingsStore()
    private let usage = UsageStore()
    private let bookmarks = BookmarkStore()
    private var model: LauncherModel!
    private var panel: LauncherPanel!
    private var controller: LauncherViewController!
    private var preferences: SettingsWindowController?
    private var statusItem: NSStatusItem?
    private var hotKeyTitle: NSMenuItem?
    private var actualHotKey: HotKeyPreset?
    private var keyMonitor: Any?
    private var scanTask: Task<Void, Never>?

    func applicationDidFinishLaunching(_ notification: Notification) {
        model = LauncherModel(settings: settings, usage: usage, executor: ActionExecutor(), bookmarks: bookmarks)
        bookmarks.onChange = { [weak self] in self?.model.refreshPreferences() }
        controller = LauncherViewController(model: model)
        panel = LauncherPanel(contentRect: NSRect(origin: .zero, size: LauncherViewController.panelSize),
                              styleMask: [], backing: .buffered, defer: false)
        panel.title = "Pennyworth"
        panel.contentViewController = controller
        panel.delegate = self
        controller.onDismiss = { [weak self] in self?.hidePanel() }
        controller.onHeightChanged = { [weak self] height in self?.resizePanel(height) }
        model.onDismiss = { [weak self] in self?.panel.orderOut(nil) }
        model.onExecutionError = { [weak self] in self?.showPanel(reset: false) }
        configureMenu()
        configureHotKey()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
               event.charactersIgnoringModifiers == "," {
                self?.showSettings(); return nil
            }
            return event
        }
        refreshApplications()
        if CommandLine.arguments.contains("--show") { showPanel() }
    }

    private func configureMenu() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: "Pennyworth")
        item.button?.toolTip = "Pennyworth"
        let menu = NSMenu()
        hotKeyTitle = menu.addItem(withTitle: "显示 Pennyworth", action: #selector(togglePanel), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "设置…", action: #selector(showSettings), keyEquivalent: ",")
        menu.addItem(withTitle: "刷新应用列表", action: #selector(refreshApplications), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "退出 Pennyworth", action: #selector(quit), keyEquivalent: "q")
        menu.items.filter { $0.action != nil }.forEach { $0.target = self }
        item.menu = menu
        statusItem = item
    }

    private func configureHotKey() {
        HotKeyManager.shared.onHotKey = { [weak self] in self?.togglePanel() }
        let requested = settings.settings.hotKey
        let candidates = [requested] + HotKeyPreset.allCases.filter { $0 != requested }
        for preset in candidates {
            do {
                try HotKeyManager.shared.register(modifiers: preset.modifiers)
                actualHotKey = preset
                hotKeyTitle?.title = "显示 Pennyworth（\(preset.title)）"
                return
            } catch { continue }
        }
        hotKeyTitle?.title = "显示 Pennyworth（热键不可用，请打开设置）"
    }

    @objc private func togglePanel() {
        if panel.isVisible { hidePanel() } else { showPanel() }
    }

    private func showPanel(reset: Bool = true) {
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) })
                ?? NSScreen.main else { return }
        let frame = screen.visibleFrame
        let width = min(LauncherViewController.panelSize.width, frame.width - 24)
        let height = min(panel.frame.height, frame.height - 24)
        panel.setFrame(NSRect(x: frame.midX - width / 2, y: min(frame.maxY - height - 12, frame.midY + 120 - height / 2),
                              width: width, height: height), display: false)
        panel.makeKeyAndOrderFront(nil)
        controller.focusSearchField(reset: reset)
    }

    private func resizePanel(_ height: CGFloat) {
        guard let panel, let screen = panel.screen ?? NSScreen.main else { return }
        let bounds = screen.visibleFrame
        let newHeight = min(height, bounds.height - 24)
        let old = panel.frame
        let y = max(bounds.minY + 12, min(old.maxY - newHeight, bounds.maxY - newHeight - 12))
        panel.setFrame(NSRect(x: old.minX, y: y, width: old.width, height: newHeight), display: true)
    }

    private func hidePanel() {
        model.endSession()
        panel.orderOut(nil)
    }

    func windowDidResignKey(_ notification: Notification) {
        guard (notification.object as? NSWindow) === panel else { return }
        if model.isExecuting { panel.orderOut(nil) } else { hidePanel() }
    }

    @objc private func showSettings() {
        hidePanel()
        if preferences == nil {
            preferences = SettingsWindowController(store: settings, usage: usage, bookmarks: bookmarks) { [weak self] value in
                guard let self else { return }
                let previous = self.actualHotKey
                try HotKeyManager.shared.register(modifiers: value.hotKey.modifiers)
                do { try self.settings.save(value) } catch {
                    if let previous { try HotKeyManager.shared.register(modifiers: previous.modifiers) }
                    throw error
                }
                self.actualHotKey = value.hotKey
                self.hotKeyTitle?.title = "显示 Pennyworth（\(value.hotKey.title)）"
                self.model.refreshPreferences()
            }
        }
        preferences?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        preferences?.window?.makeKeyAndOrderFront(nil)
    }

    @objc private func refreshApplications() {
        guard scanTask == nil else { return }
        scanTask = Task { [weak self] in
            let apps = await Task.detached(priority: .userInitiated) { AppScanner.scanInstalledApplications() }.value
            guard let self else { return }
            self.model.setApplications(apps)
            self.scanTask = nil
        }
    }

    @objc private func quit() { NSApp.terminate(nil) }

    func applicationWillTerminate(_ notification: Notification) {
        model.endSession()
        HotKeyManager.shared.unregister()
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        scanTask?.cancel()
    }
}
