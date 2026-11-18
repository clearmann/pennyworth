import AppKit
import Carbon

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let settings: SettingsStore
    private let usage: UsageStore
    private let bookmarks: BookmarkStore
    private let clipboardStore: ClipboardStore
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
    private var screenshotHotKeyTitle: NSMenuItem?
    private var actualHotKey: HotKeyPreset?
    private var actualClipboardHotKey: HotKeyPreset?
    private var actualScreenshotHotKey: HotKeyPreset?
    private var pinnedImageManager: PinnedImageManager!
    private var screenshotController: ScreenshotSessionController!
    private var screenshotHotKeyAlertShown = false
    private var scanTask: Task<Void, Never>?
    private var clipboardTimer: Timer?
    private let focusRestorer = ApplicationFocusRestorer(frontmostApplication: {
        NSWorkspace.shared.frontmostApplication
    })

    override init() {
        let savedSettings = SettingsStore()
        AppLocalization.configure(language: savedSettings.settings.language)
        settings = savedSettings
        usage = UsageStore()
        bookmarks = BookmarkStore()
        clipboardStore = ClipboardStore()
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        pinnedImageManager = PinnedImageManager()
        let output = ScreenshotOutputHandler(pinnedImageManager: pinnedImageManager)
        let permission = ScreenCapturePermissionCoordinator(
            access: SystemScreenCaptureAccess(),
            guidance: AlertScreenCaptureGuidancePresenter(),
            settingsOpener: SystemScreenCaptureSettingsOpener()
        )
        screenshotController = ScreenshotSessionController(
            capturer: ScreenCapturerFactory.make(),
            permission: permission,
            overlay: ScreenshotOverlayController(),
            output: output
        )
        screenshotController.onWillCapture = { [weak self] in
            guard let self else { return }
            self.focusRestorer.captureFrontmostApplication()
            self.hidePanel()
            self.hideClipboardPanel()
        }
        screenshotController.onCancelRestoreFocus = { [weak self] in
            self?.focusRestorer.restorePreviousApplication()
        }
        screenshotController.onError = { [weak self] error in
            self?.showScreenshotError(error)
        }

        model = LauncherModel(settings: settings, usage: usage,
                              executor: ActionExecutor(screenshotActions: screenshotController), bookmarks: bookmarks)
        bookmarks.onChange = { [weak self] in self?.model.refreshPreferences() }
        controller = LauncherViewController(model: model)
        panel = LauncherPanel(contentRect: NSRect(origin: .zero, size: LauncherViewController.panelSize),
                              styleMask: [], backing: .buffered, defer: false)
        panel.title = "Pennyworth"
        panel.contentViewController = controller
        panel.delegate = self
        controller.onDismiss = { [weak self] in self?.dismissPanel() }
        controller.onSettings = { [weak self] in self?.showSettings() }
        controller.onHeightChanged = { [weak self] height in self?.resizePanel(self?.panel, height: height) }
        model.onDismiss = { [weak self] in self?.panel.orderOut(nil) }
        model.onExecutionError = { [weak self] in self?.showPanel(reset: false) }

        clipboardController = ClipboardHistoryViewController(
            model: ClipboardHistoryModel(items: clipboardStore.items),
            onRestore: { [weak self] item in self?.restoreClipboard(item) }
        )
        clipboardPanel = LauncherPanel(contentRect: NSRect(origin: .zero, size: ClipboardHistoryViewController.panelSize),
                                       styleMask: [], backing: .buffered, defer: false)
        clipboardPanel.title = L10n.tr("clipboard.window_title")
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
        hotKeyTitle = menu.addItem(withTitle: L10n.tr("menu.show_launcher"), action: #selector(togglePanel), keyEquivalent: "")
        clipboardHotKeyTitle = menu.addItem(withTitle: L10n.tr("menu.show_clipboard"), action: #selector(toggleClipboardPanel), keyEquivalent: "")
        menu.addItem(.separator())
        screenshotHotKeyTitle = menu.addItem(withTitle: L10n.tr("menu.screenshot"), action: #selector(startScreenshotFromMenu), keyEquivalent: "")
        menu.addItem(withTitle: L10n.tr("menu.pin_clipboard"), action: #selector(pinClipboardFromMenu), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: L10n.tr("menu.settings"), action: #selector(showSettings), keyEquivalent: ",")
        menu.addItem(withTitle: L10n.tr("menu.refresh_apps"), action: #selector(refreshApplications), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: L10n.tr("menu.quit"), action: #selector(quit), keyEquivalent: "q")
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
        registerScreenshotHotKey(settings.settings.screenshotHotKey)
        hotKeyTitle?.title = actualHotKey.map { L10n.format("menu.show_launcher_hotkey", $0.title) }
            ?? L10n.tr("menu.launcher_hotkey_unavailable")
        clipboardHotKeyTitle?.title = actualClipboardHotKey.map { L10n.format("menu.show_clipboard_hotkey", $0.title) }
            ?? L10n.tr("menu.clipboard_hotkey_unavailable")
        updateScreenshotHotKeyTitle()
    }

    /// Direct named registration only: no candidate fallback, no silent failure.
    private func registerScreenshotHotKey(_ preset: HotKeyPreset?) {
        actualScreenshotHotKey = nil
        guard let preset else { return }
        do {
            try HotKeyManager.shared.register(name: "screenshot", keyCode: preset.keyCode,
                                              modifiers: preset.modifiers) { [weak self] in
                try? self?.screenshotController.startScreenshot()
            }
            actualScreenshotHotKey = preset
        } catch {
            actualScreenshotHotKey = nil
            if !screenshotHotKeyAlertShown {
                screenshotHotKeyAlertShown = true
                DispatchQueue.main.async { [weak self] in self?.showHotKeyRegistrationAlert(preset) }
            }
        }
    }

    private func updateScreenshotHotKeyTitle() {
        if settings.settings.screenshotHotKey == nil {
            screenshotHotKeyTitle?.title = L10n.tr("menu.screenshot_hotkey_not_set")
        } else if let actual = actualScreenshotHotKey {
            screenshotHotKeyTitle?.title = L10n.format("menu.screenshot_hotkey", actual.title)
        } else {
            screenshotHotKeyTitle?.title = L10n.tr("menu.screenshot_hotkey_unavailable")
        }
    }

    private func showHotKeyRegistrationAlert(_ preset: HotKeyPreset) {
        let alert = NSAlert()
        alert.messageText = L10n.tr("menu.screenshot")
        alert.informativeText = L10n.format("screenshot.error.hotkey_registration_failed", preset.title)
        alert.addButton(withTitle: L10n.tr("menu.settings"))
        alert.addButton(withTitle: L10n.tr("screenshot.action.cancel"))
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn { presentSettings() }
    }

    @objc private func startScreenshotFromMenu() {
        do { try screenshotController.startScreenshot() } catch { showScreenshotError(error) }
    }

    @objc private func pinClipboardFromMenu() {
        do { try screenshotController.pinClipboardImage() } catch { showScreenshotError(error) }
    }

    private func showScreenshotError(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = L10n.tr("menu.screenshot")
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        alert.addButton(withTitle: L10n.tr("common.ok"))
        // The overlay sits at .screenSaver level; the alert must float above it.
        alert.window.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1)
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
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
        screenshotController.cancel()
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
            if let preset = value.screenshotHotKey {
                try HotKeyManager.shared.register(name: "screenshot", keyCode: preset.keyCode,
                                                  modifiers: preset.modifiers) { [weak self] in
                    try? self?.screenshotController.startScreenshot()
                }
            } else {
                HotKeyManager.shared.unregister(name: "screenshot")
            }
            try settings.save(value)
            actualHotKey = value.hotKey
            actualClipboardHotKey = value.clipboardHotKey
            actualScreenshotHotKey = value.screenshotHotKey
            hotKeyTitle?.title = L10n.format("menu.show_launcher_hotkey", value.hotKey.title)
            clipboardHotKeyTitle?.title = L10n.format("menu.show_clipboard_hotkey", value.clipboardHotKey.title)
            updateScreenshotHotKeyTitle()
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
            if let preset = previous.screenshotHotKey {
                try? HotKeyManager.shared.register(name: "screenshot", keyCode: preset.keyCode,
                                                   modifiers: preset.modifiers) { [weak self] in
                    try? self?.screenshotController.startScreenshot()
                }
            } else {
                HotKeyManager.shared.unregister(name: "screenshot")
            }
            actualScreenshotHotKey = previous.screenshotHotKey
            updateScreenshotHotKeyTitle()
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
            let language = AppLocalization.currentLanguage
            let apps = await Task.detached(priority: .userInitiated) {
                AppScanner.scanInstalledApplications(language: language)
            }.value
            guard let self else { return }
            self.model.setApplications(apps)
            self.scanTask = nil
        }
    }

    @objc private func quit() { NSApp.terminate(nil) }

    func applicationWillTerminate(_ notification: Notification) {
        screenshotController.cancel()
        pinnedImageManager.closeAll()
        model.endSession()
        clipboardTimer?.invalidate()
        HotKeyManager.shared.unregister()
        scanTask?.cancel()
    }
}
