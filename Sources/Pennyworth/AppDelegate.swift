import AppKit
import Carbon

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let settings = SettingsStore()
    private let usage = UsageStore()
    private let bookmarks = BookmarkStore()
    private let clipboardStore = ClipboardStore()
    private let clipboardMonitor = ClipboardMonitor()
    private var model: LauncherModel!
    private var panel: LauncherPanel!
    private var controller: LauncherViewController!
    private var clipboardPanel: LauncherPanel!
    private var clipboardController: ClipboardHistoryViewController!
    private var preferences: SettingsWindowController?
    private var statusItem: NSStatusItem?
    private var hotKeyTitle: NSMenuItem?
    private var clipboardHotKeyTitle: NSMenuItem?
    private var actualHotKey: HotKeyPreset?
    private var actualClipboardHotKey: HotKeyPreset?
    private var scanTask: Task<Void, Never>?
    private var clipboardTimer: Timer?
    private let focusRestorer = ApplicationFocusRestorer(frontmostApplication: {
        NSWorkspace.shared.frontmostApplication
    })

    func applicationDidFinishLaunching(_ notification: Notification) {
        model = LauncherModel(settings: settings, usage: usage, executor: ActionExecutor(), bookmarks: bookmarks)
        bookmarks.onChange = { [weak self] in self?.model.refreshPreferences() }
        controller = LauncherViewController(model: model)
        panel = LauncherPanel(contentRect: NSRect(origin: .zero, size: LauncherViewController.panelSize),
                              styleMask: [], backing: .buffered, defer: false)
        panel.title = "Pennyworth"
        panel.contentViewController = controller
        panel.delegate = self
        controller.onDismiss = { [weak self] in self?.dismissPanel() }
        controller.onHeightChanged = { [weak self] height in self?.resizePanel(self?.panel, height: height) }
        model.onDismiss = { [weak self] in self?.panel.orderOut(nil) }
        model.onExecutionError = { [weak self] in self?.showPanel(reset: false) }

        clipboardController = ClipboardHistoryViewController(
            model: ClipboardHistoryModel(items: clipboardStore.items),
            onRestore: { [weak self] item in self?.restoreClipboard(item) }
        )
        clipboardPanel = LauncherPanel(contentRect: NSRect(origin: .zero, size: ClipboardHistoryViewController.panelSize),
                                       styleMask: [], backing: .buffered, defer: false)
        clipboardPanel.title = "Pennyworth 剪贴板历史"
        clipboardPanel.contentViewController = clipboardController
        clipboardPanel.delegate = self
        clipboardController.onDismiss = { [weak self] in self?.hideClipboardPanel() }
        clipboardController.onHeightChanged = { [weak self] height in
            self?.resizePanel(self?.clipboardPanel, height: height)
        }

        configureMenu()
        configureHotKeys()
        refreshApplications()
        startClipboardMonitoring()
        if CommandLine.arguments.contains("--show") { showPanel() }
    }

    private func configureMenu() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: "Pennyworth")
        item.button?.toolTip = "Pennyworth"
        let menu = NSMenu()
        hotKeyTitle = menu.addItem(withTitle: "显示 Pennyworth", action: #selector(togglePanel), keyEquivalent: "")
        clipboardHotKeyTitle = menu.addItem(withTitle: "显示剪贴板历史", action: #selector(toggleClipboardPanel), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "设置…", action: #selector(showSettings), keyEquivalent: ",")
        menu.addItem(withTitle: "刷新应用列表", action: #selector(refreshApplications), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "退出 Pennyworth", action: #selector(quit), keyEquivalent: "q")
        menu.items.filter { $0.action != nil }.forEach { $0.target = self }
        item.menu = menu
        statusItem = item
    }

    private func configureHotKeys() {
        HotKeyManager.shared.unregister()
        actualHotKey = registerStartupHotKey(name: "launcher", requested: settings.settings.hotKey,
                                             candidates: HotKeyPreset.launcherPresets) { [weak self] in
            self?.togglePanel()
        }
        actualClipboardHotKey = registerStartupHotKey(name: "clipboard", requested: settings.settings.clipboardHotKey,
                                                       candidates: HotKeyPreset.clipboardPresets) { [weak self] in
            self?.toggleClipboardPanel()
        }
        try? HotKeyManager.shared.register(name: "settings", keyCode: HotKeyPreset.commandComma.keyCode,
                                            modifiers: HotKeyPreset.commandComma.modifiers) { [weak self] in
            self?.showSettings()
        }
        hotKeyTitle?.title = actualHotKey.map { "显示 Pennyworth（\($0.title)）" }
            ?? "显示 Pennyworth（热键不可用，请打开设置）"
        clipboardHotKeyTitle?.title = actualClipboardHotKey.map { "显示剪贴板历史（\($0.title)）" }
            ?? "显示剪贴板历史（热键不可用，请打开设置）"
    }

    private func registerStartupHotKey(name: String, requested: HotKeyPreset, candidates: [HotKeyPreset],
                                       callback: @escaping () -> Void) -> HotKeyPreset? {
        let options = requested.isCustom ? [requested] : [requested] + candidates.filter({ $0 != requested })
        for preset in options {
            do {
                try HotKeyManager.shared.register(name: name, keyCode: preset.keyCode,
                                                  modifiers: preset.modifiers, callback: callback)
                return preset
            } catch { continue }
        }
        return nil
    }

    @objc private func togglePanel() {
        if panel.isVisible { hidePanel() } else { showPanel() }
    }

    @objc private func toggleClipboardPanel() {
        if clipboardPanel.isVisible { hideClipboardPanel() } else { showClipboardPanel() }
    }

    private func showPanel(reset: Bool = true) {
        focusRestorer.captureFrontmostApplication()
        show(panel, size: LauncherViewController.panelSize)
        controller.focusSearchField(reset: reset)
    }

    private func showClipboardPanel() {
        clipboardController.updateItems(clipboardStore.items)
        show(clipboardPanel, size: ClipboardHistoryViewController.panelSize)
        clipboardController.focusSearchField()
    }

    private func show(_ target: NSPanel, size: NSSize) {
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) })
                ?? NSScreen.main else { return }
        let frame = screen.visibleFrame
        let width = min(size.width, frame.width - 24)
        let height = min(target.frame.height, frame.height - 24)
        target.setFrame(NSRect(x: frame.midX - width / 2,
                               y: min(frame.maxY - height - 12, frame.midY + 120 - height / 2),
                               width: width, height: height), display: false)
        target.makeKeyAndOrderFront(nil)
    }

    private func resizePanel(_ target: NSPanel?, height: CGFloat) {
        guard let target, let screen = target.screen ?? NSScreen.main else { return }
        let bounds = screen.visibleFrame
        let newHeight = min(height, bounds.height - 24)
        let old = target.frame
        let y = max(bounds.minY + 12, min(old.maxY - newHeight, bounds.maxY - newHeight - 12))
        target.setFrame(NSRect(x: old.minX, y: y, width: old.width, height: newHeight), display: true)
    }

    private func dismissPanel() {
        hidePanel()
        focusRestorer.restorePreviousApplication()
    }

    private func hidePanel() {
        model.endSession()
        panel.orderOut(nil)
    }

    private func hideClipboardPanel() {
        clipboardPanel.orderOut(nil)
    }

    func windowDidResignKey(_ notification: Notification) {
        if (notification.object as? NSWindow) === panel {
            if model.isExecuting { panel.orderOut(nil) } else { hidePanel() }
        } else if (notification.object as? NSWindow) === clipboardPanel {
            hideClipboardPanel()
        }
    }

    @objc private func showSettings() {
        DispatchQueue.main.async { [weak self] in
            self?.presentSettings()
        }
    }

    private func presentSettings() {
        hidePanel()
        hideClipboardPanel()
        if preferences == nil {
            preferences = SettingsWindowController(store: settings, usage: usage, bookmarks: bookmarks) { [weak self] value in
                try self?.applySettings(value)
            }
        }
        NSApp.activate(ignoringOtherApps: true)
        preferences?.showWindow(nil)
        preferences?.window?.makeKeyAndOrderFront(nil)
    }

    private func applySettings(_ value: LauncherSettings) throws {
        let previous = settings.settings
        do {
            try HotKeyManager.shared.register(name: "launcher", keyCode: value.hotKey.keyCode,
                                              modifiers: value.hotKey.modifiers) { [weak self] in
                self?.togglePanel()
            }
            try HotKeyManager.shared.register(name: "clipboard", keyCode: value.clipboardHotKey.keyCode,
                                              modifiers: value.clipboardHotKey.modifiers) { [weak self] in
                self?.toggleClipboardPanel()
            }
            try settings.save(value)
            actualHotKey = value.hotKey
            actualClipboardHotKey = value.clipboardHotKey
            hotKeyTitle?.title = "显示 Pennyworth（\(value.hotKey.title)）"
            clipboardHotKeyTitle?.title = "显示剪贴板历史（\(value.clipboardHotKey.title)）"
            model.refreshPreferences()
        } catch {
            try? HotKeyManager.shared.register(name: "launcher", keyCode: previous.hotKey.keyCode,
                                               modifiers: previous.hotKey.modifiers) { [weak self] in
                self?.togglePanel()
            }
            try? HotKeyManager.shared.register(name: "clipboard", keyCode: previous.clipboardHotKey.keyCode,
                                               modifiers: previous.clipboardHotKey.modifiers) { [weak self] in
                self?.toggleClipboardPanel()
            }
            throw error
        }
    }

    private func startClipboardMonitoring() {
        clipboardTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.captureClipboard() }
        }
    }

    private func captureClipboard() {
        guard let item = clipboardMonitor.checkPasteboard() else { return }
        clipboardStore.add(item)
        clipboardController.updateItems(clipboardStore.items)
    }

    private func restoreClipboard(_ item: ClipboardItem) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        let written: Bool
        switch item.content {
        case .text(let value): written = pasteboard.setString(value, forType: .string)
        case .image(let image, _): written = pasteboard.writeObjects([image])
        case .file(let url): written = pasteboard.writeObjects([url as NSURL])
        }
        if written {
            clipboardMonitor.markCurrentChangeAsSeen()
            hideClipboardPanel()
        }
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
        clipboardTimer?.invalidate()
        HotKeyManager.shared.unregister()
        scanTask?.cancel()
    }
}
