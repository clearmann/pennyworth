import AppKit
import Carbon

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let settings: SettingsStore
    private let usage: UsageStore
    private let bookmarks: BookmarkStore
    private let clipboardStore: ClipboardStore
    private let clipboardMonitor = ClipboardMonitor()
    private let uploadSecretStore: ImageUploadSecretStoring = KeychainSecretStore()
    private let uploadHistoryStore = UploadHistoryStore()
    private let uploadToast = UploadStatusToast()
    private var model: LauncherModel!
    private var panel: LauncherPanel!
    private var controller: LauncherViewController!
    private var clipboardPanel: LauncherPanel!
    private var clipboardController: ClipboardHistoryViewController!
    private var preferences: SettingsWindowController?
    private var statusItem: NSStatusItem?
    private var statusBarDropView: StatusBarDropView?
    private var hotKeyTitle: NSMenuItem?
    private var clipboardHotKeyTitle: NSMenuItem?
    private var screenshotHotKeyTitle: NSMenuItem?
    private var uploadFileMenuItem: NSMenuItem?
    private var uploadClipboardMenuItem: NSMenuItem?
    private var uploadHostsSubmenu: NSMenu?
    private var uploadFormatSubmenu: NSMenu?
    private var uploadHistorySubmenu: NSMenu?
    private var actualHotKey: HotKeyPreset?
    private var actualClipboardHotKey: HotKeyPreset?
    private var actualScreenshotHotKey: HotKeyPreset?
    private var actualUploadClipboardHotKey: HotKeyPreset?
    private var actualUploadFileHotKey: HotKeyPreset?
    private var pinnedImageManager: PinnedImageManager!
    private var screenshotController: ScreenshotSessionController!
    private var mouseScrollController: MouseScrollController!
    private var imageUploadController: ImageUploadController!
    private var screenshotHotKeyAlertShown = false
    private var uploadHotKeyAlertShown = false
    private var installedApplications: [AppItem] = []
    private let appShortcutLauncher: AppShortcutLaunching = AppShortcutLauncher()
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

        imageUploadController = ImageUploadController(
            settingsProvider: { [weak self] in self?.settings.settings.imageUpload ?? .defaults },
            service: ImageUploadService(secretStore: uploadSecretStore),
            historyStore: uploadHistoryStore,
            onFeedback: { [weak self] title, detail, style in
                self?.uploadToast.show(title: title, detail: detail, style: style)
            }
        )
        imageUploadController.onStateChanged = { [weak self] state in
            self?.updateStatusItemAppearance(for: state)
        }
        imageUploadController.onHistoryChanged = { [weak self] in
            self?.rebuildUploadHistoryMenu()
            self?.preferences?.reloadImageUploadHistory()
        }

        configureMenu()
        configureHotKeys()
        mouseScrollController = MouseScrollController()
        mouseScrollController.onStatusChange = { [weak self] _ in
            self?.preferences?.reloadMouseStatus()
        }
        mouseScrollController.apply(settings.settings.mouseScroll, promptForPermission: false)
        refreshApplications()
        startClipboardMonitoring()
        if CommandLine.arguments.contains("--show") { showPanel() }
    }

    private func configureMenu() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: "Pennyworth")
        item.button?.toolTip = "Pennyworth"
        if let button = item.button {
            let dropView = StatusBarDropView(frame: button.bounds)
            dropView.autoresizingMask = [.width, .height]
            dropView.onDragHoverChanged = { [weak self] hovering in
                self?.imageUploadController.setDragHovering(hovering)
            }
            dropView.onDropFiles = { [weak self] urls in
                self?.imageUploadController.uploadFiles(urls)
            }
            button.addSubview(dropView)
            statusBarDropView = dropView
        }
        let menu = NSMenu()
        hotKeyTitle = menu.addItem(withTitle: L10n.tr("menu.show_launcher"), action: #selector(togglePanel), keyEquivalent: "")
        clipboardHotKeyTitle = menu.addItem(withTitle: L10n.tr("menu.show_clipboard"), action: #selector(toggleClipboardPanel), keyEquivalent: "")
        menu.addItem(.separator())
        screenshotHotKeyTitle = menu.addItem(withTitle: L10n.tr("menu.screenshot"), action: #selector(startScreenshotFromMenu), keyEquivalent: "")
        menu.addItem(withTitle: L10n.tr("menu.pin_clipboard"), action: #selector(pinClipboardFromMenu), keyEquivalent: "")
        menu.addItem(.separator())
        uploadFileMenuItem = menu.addItem(withTitle: L10n.tr("menu.upload_file"), action: #selector(uploadFileFromMenu), keyEquivalent: "")
        uploadClipboardMenuItem = menu.addItem(withTitle: L10n.tr("menu.upload_clipboard"), action: #selector(uploadClipboardFromMenu), keyEquivalent: "")

        let hostsItem = NSMenuItem(title: L10n.tr("menu.upload_hosts"), action: nil, keyEquivalent: "")
        let hostsMenu = NSMenu()
        hostsItem.submenu = hostsMenu
        uploadHostsSubmenu = hostsMenu
        menu.addItem(hostsItem)

        let formatItem = NSMenuItem(title: L10n.tr("menu.upload_format"), action: nil, keyEquivalent: "")
        let formatMenu = NSMenu()
        formatItem.submenu = formatMenu
        uploadFormatSubmenu = formatMenu
        menu.addItem(formatItem)

        let historyItem = NSMenuItem(title: L10n.tr("menu.upload_history"), action: nil, keyEquivalent: "")
        let historyMenu = NSMenu()
        historyItem.submenu = historyMenu
        uploadHistorySubmenu = historyMenu
        menu.addItem(historyItem)

        menu.addItem(.separator())
        menu.addItem(withTitle: L10n.tr("menu.settings"), action: #selector(showSettings), keyEquivalent: ",")
        menu.addItem(withTitle: L10n.tr("menu.refresh_apps"), action: #selector(refreshApplications), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: L10n.tr("menu.quit"), action: #selector(quit), keyEquivalent: "q")
        menu.items.filter { $0.action != nil }.forEach { $0.target = self }
        item.menu = menu
        statusItem = item
        rebuildUploadMenus()
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
        registerUploadHotKeys(settings.settings.imageUpload)
        HotKeyConfigurationApplier.registerStartupAppShortcuts(
            settings.settings.appShortcuts,
            in: HotKeyManager.shared
        ) { [weak self] shortcut in
            self?.triggerAppShortcut(shortcut)
        }
        hotKeyTitle?.title = actualHotKey.map { L10n.format("menu.show_launcher_hotkey", $0.title) }
            ?? L10n.tr("menu.launcher_hotkey_unavailable")
        clipboardHotKeyTitle?.title = actualClipboardHotKey.map { L10n.format("menu.show_clipboard_hotkey", $0.title) }
            ?? L10n.tr("menu.clipboard_hotkey_unavailable")
        updateScreenshotHotKeyTitle()
        updateUploadHotKeyTitles()
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

    /// Direct named registration only: no candidate fallback, no silent failure.
    private func registerUploadHotKeys(_ uploadSettings: ImageUploadSettings) {
        actualUploadClipboardHotKey = registerOptionalNamedHotKey(
            name: "uploadClipboard",
            preset: uploadSettings.uploadClipboardHotKey,
            featureTitle: L10n.tr("menu.upload_clipboard")
        ) { [weak self] in
            self?.imageUploadController.uploadClipboard()
        }
        actualUploadFileHotKey = registerOptionalNamedHotKey(
            name: "uploadFile",
            preset: uploadSettings.uploadFileHotKey,
            featureTitle: L10n.tr("menu.upload_file")
        ) { [weak self] in
            self?.imageUploadController.selectFilesAndUpload()
        }
    }

    private func registerOptionalNamedHotKey(
        name: String,
        preset: HotKeyPreset?,
        featureTitle: String,
        callback: @escaping () -> Void
    ) -> HotKeyPreset? {
        guard let preset else { return nil }
        do {
            try HotKeyManager.shared.register(name: name, keyCode: preset.keyCode, modifiers: preset.modifiers, callback: callback)
            return preset
        } catch {
            if !uploadHotKeyAlertShown {
                uploadHotKeyAlertShown = true
                DispatchQueue.main.async { [weak self] in
                    self?.showNamedHotKeyRegistrationAlert(title: featureTitle, preset: preset)
                }
            }
            return nil
        }
    }

    private func showNamedHotKeyRegistrationAlert(title: String, preset: HotKeyPreset) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = L10n.format("image_upload.error.hotkey_registration_failed", preset.title)
        alert.addButton(withTitle: L10n.tr("menu.settings"))
        alert.addButton(withTitle: L10n.tr("common.cancel"))
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            presentSettings(initialPage: L10n.tr("settings.page.image_upload"))
        }
    }

    private func updateUploadHotKeyTitles() {
        let uploadSettings = settings.settings.imageUpload
        if uploadSettings.uploadFileHotKey == nil {
            uploadFileMenuItem?.title = L10n.tr("menu.upload_file")
        } else if let actual = actualUploadFileHotKey {
            uploadFileMenuItem?.title = L10n.format("menu.upload_file_hotkey", actual.title)
        } else {
            uploadFileMenuItem?.title = L10n.tr("menu.upload_file_hotkey_unavailable")
        }

        if uploadSettings.uploadClipboardHotKey == nil {
            uploadClipboardMenuItem?.title = L10n.tr("menu.upload_clipboard")
        } else if let actual = actualUploadClipboardHotKey {
            uploadClipboardMenuItem?.title = L10n.format("menu.upload_clipboard_hotkey", actual.title)
        } else {
            uploadClipboardMenuItem?.title = L10n.tr("menu.upload_clipboard_hotkey_unavailable")
        }
    }

    private func rebuildUploadMenus() {
        rebuildUploadHostsMenu()
        rebuildUploadFormatMenu()
        rebuildUploadHistoryMenu()
    }

    private func rebuildUploadHostsMenu() {
        guard let menu = uploadHostsSubmenu else { return }
        menu.removeAllItems()
        let uploadSettings = settings.settings.imageUpload
        if uploadSettings.hosts.isEmpty {
            let item = menu.addItem(
                withTitle: L10n.tr("menu.upload_configure_hosts"),
                action: #selector(openImageUploadSettings),
                keyEquivalent: ""
            )
            item.target = self
            return
        }
        let activeID = uploadSettings.activeHost?.id
        for host in uploadSettings.hosts {
            let item = menu.addItem(
                withTitle: "\(host.name) (\(host.provider.title))",
                action: #selector(selectUploadHostFromMenu(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = host.id
            item.state = host.id == activeID ? .on : .off
        }
    }

    private func rebuildUploadFormatMenu() {
        guard let menu = uploadFormatSubmenu else { return }
        menu.removeAllItems()
        let currentFormat = settings.settings.imageUpload.outputFormat
        for format in UploadOutputFormat.allCases {
            let item = menu.addItem(
                withTitle: format.title,
                action: #selector(selectUploadFormatFromMenu(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = format.rawValue
            item.state = format == currentFormat ? .on : .off
        }
    }

    private func rebuildUploadHistoryMenu() {
        guard let menu = uploadHistorySubmenu else { return }
        menu.removeAllItems()
        let recent = Array(uploadHistoryStore.items.prefix(10))
        if recent.isEmpty {
            let emptyItem = menu.addItem(withTitle: L10n.tr("menu.upload_history_empty"), action: nil, keyEquivalent: "")
            emptyItem.isEnabled = false
            return
        }
        for record in recent {
            let title = "\(record.filename) · \(record.hostName)"
            let item = menu.addItem(
                withTitle: title,
                action: #selector(copyUploadHistoryFromMenu(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = record.id
            item.toolTip = record.url
            if let data = record.thumbnailData, let image = NSImage(data: data) {
                image.size = NSSize(width: 18, height: 18)
                item.image = image
            }
        }
        menu.addItem(.separator())
        let clearItem = menu.addItem(
            withTitle: L10n.tr("image_upload.history.clear"),
            action: #selector(clearUploadHistoryFromMenu),
            keyEquivalent: ""
        )
        clearItem.target = self
    }

    private func updateStatusItemAppearance(for state: ImageUploadController.VisualState) {
        guard let button = statusItem?.button else { return }
        switch state {
        case .idle:
            button.image = NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: "Pennyworth")
            button.toolTip = "Pennyworth"
        case .dragHover:
            button.image = NSImage(systemSymbolName: "icloud.and.arrow.up.fill", accessibilityDescription: L10n.tr("image_upload.status.drop_hint"))
            button.toolTip = L10n.tr("image_upload.status.drop_hint")
        case .uploading:
            button.image = NSImage(systemSymbolName: "icloud.and.arrow.up", accessibilityDescription: L10n.tr("image_upload.status.uploading"))
            button.toolTip = L10n.tr("image_upload.status.uploading")
        case .succeeded:
            button.image = NSImage(systemSymbolName: "checkmark.circle", accessibilityDescription: L10n.tr("image_upload.toast.success_title"))
            button.toolTip = L10n.tr("image_upload.toast.success_title")
        }
    }

    @objc private func uploadFileFromMenu() {
        imageUploadController.selectFilesAndUpload()
    }

    @objc private func uploadClipboardFromMenu() {
        imageUploadController.uploadClipboard()
    }

    @objc private func openImageUploadSettings() {
        presentSettings(initialPage: L10n.tr("settings.page.image_upload"))
    }

    @objc private func selectUploadHostFromMenu(_ sender: NSMenuItem) {
        guard let hostID = sender.representedObject as? String else { return }
        let current = settings.settings
        let updated = LauncherSettings(
            hotKey: current.hotKey,
            searchDirectories: current.searchDirectories,
            searchEngine: current.searchEngine,
            rememberUsage: current.rememberUsage,
            webSearches: current.webSearches,
            fallbackOnlyWhenNoResults: current.fallbackOnlyWhenNoResults,
            clipboardHotKey: current.clipboardHotKey,
            language: current.language,
            screenshotHotKey: current.screenshotHotKey,
            appShortcuts: current.appShortcuts,
            mouseScroll: current.mouseScroll,
            imageUpload: current.imageUpload.withSelectedHostID(hostID)
        )
        try? settings.save(updated)
        rebuildUploadHostsMenu()
    }

    @objc private func selectUploadFormatFromMenu(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let format = UploadOutputFormat(rawValue: raw) else { return }
        let current = settings.settings
        let updated = LauncherSettings(
            hotKey: current.hotKey,
            searchDirectories: current.searchDirectories,
            searchEngine: current.searchEngine,
            rememberUsage: current.rememberUsage,
            webSearches: current.webSearches,
            fallbackOnlyWhenNoResults: current.fallbackOnlyWhenNoResults,
            clipboardHotKey: current.clipboardHotKey,
            language: current.language,
            screenshotHotKey: current.screenshotHotKey,
            appShortcuts: current.appShortcuts,
            mouseScroll: current.mouseScroll,
            imageUpload: current.imageUpload.withOutputFormat(format)
        )
        try? settings.save(updated)
        rebuildUploadFormatMenu()
    }

    @objc private func copyUploadHistoryFromMenu(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String,
              let item = uploadHistoryStore.items.first(where: { $0.id == id }) else { return }
        imageUploadController.copyHistoryItem(item)
    }

    @objc private func clearUploadHistoryFromMenu() {
        imageUploadController.clearHistory()
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

    private func presentSettings(initialPage: String? = nil) {
        screenshotController.cancel()
        hidePanel()
        hideClipboardPanel()
        if preferences == nil {
            preferences = SettingsWindowController(
                store: settings,
                usage: usage,
                bookmarks: bookmarks,
                applicationsProvider: { [weak self] in self?.installedApplications ?? [] },
                setHotKeySuspended: { HotKeyManager.shared.setSuspended($0) },
                mousePermissionProvider: { [weak self] in
                    guard let controller = self?.mouseScrollController else { return (.inactive, false) }
                    return (controller.status, controller.isAccessibilityTrusted)
                },
                onRequestMousePermission: { [weak self] in
                    self?.mouseScrollController.requestPermission()
                },
                onOpenMouseAccessibilitySettings: { [weak self] in
                    self?.mouseScrollController.openAccessibilitySettings() ?? false
                },
                onRefreshMousePermission: { [weak self] in
                    self?.mouseScrollController.refreshPermissionStatus()
                },
                imageUploadSecretStore: uploadSecretStore,
                uploadHistoryProvider: { [weak self] in self?.uploadHistoryStore.items ?? [] },
                onCopyUploadHistory: { [weak self] item in
                    self?.imageUploadController.copyHistoryItem(item)
                },
                onClearUploadHistory: { [weak self] in
                    self?.imageUploadController.clearHistory()
                }
            ) { [weak self] value in
                try self?.applySettings(value)
            }
        }
        NSApp.activate(ignoringOtherApps: true)
        preferences?.showWindow(nil)
        if let initialPage {
            preferences?.selectPage(initialPage)
        }
        preferences?.window?.makeKeyAndOrderFront(nil)
    }

    private func triggerAppShortcut(_ shortcut: AppShortcut) {
        hidePanel()
        hideClipboardPanel()
        appShortcutLauncher.launch(shortcut)
    }

    private func applySettings(_ value: LauncherSettings) throws {
        let previous = settings.settings
        try HotKeyConfigurationApplier.apply(
            next: value,
            previous: previous,
            manager: HotKeyManager.shared,
            onLauncher: { [weak self] in self?.togglePanel() },
            onClipboard: { [weak self] in self?.toggleClipboardPanel() },
            onScreenshot: { [weak self] in try? self?.screenshotController.startScreenshot() },
            onUploadClipboard: { [weak self] in self?.imageUploadController.uploadClipboard() },
            onUploadFile: { [weak self] in self?.imageUploadController.selectFilesAndUpload() },
            onAppShortcut: { [weak self] shortcut in self?.triggerAppShortcut(shortcut) }
        )
        do {
            try settings.save(value)
        } catch {
            HotKeyConfigurationApplier.restore(
                previous,
                afterUnregistering: value,
                in: HotKeyManager.shared,
                onLauncher: { [weak self] in self?.togglePanel() },
                onClipboard: { [weak self] in self?.toggleClipboardPanel() },
                onScreenshot: { [weak self] in try? self?.screenshotController.startScreenshot() },
                onUploadClipboard: { [weak self] in self?.imageUploadController.uploadClipboard() },
                onUploadFile: { [weak self] in self?.imageUploadController.selectFilesAndUpload() },
                onAppShortcut: { [weak self] shortcut in self?.triggerAppShortcut(shortcut) }
            )
            throw error
        }
        actualHotKey = value.hotKey
        actualClipboardHotKey = value.clipboardHotKey
        actualScreenshotHotKey = value.screenshotHotKey
        actualUploadClipboardHotKey = value.imageUpload.uploadClipboardHotKey
        actualUploadFileHotKey = value.imageUpload.uploadFileHotKey
        mouseScrollController.apply(
            value.mouseScroll,
            promptForPermission: value.mouseScroll.isActive && !previous.mouseScroll.isActive
        )
        hotKeyTitle?.title = L10n.format("menu.show_launcher_hotkey", value.hotKey.title)
        clipboardHotKeyTitle?.title = L10n.format("menu.show_clipboard_hotkey", value.clipboardHotKey.title)
        updateScreenshotHotKeyTitle()
        updateUploadHotKeyTitles()
        rebuildUploadMenus()
        model.refreshPreferences()
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
            self.installedApplications = apps
            self.model.setApplications(apps)
            self.preferences?.reloadApplications(apps)
            self.scanTask = nil
        }
    }

    @objc private func quit() { NSApp.terminate(nil) }

    func applicationWillTerminate(_ notification: Notification) {
        uploadToast.dismiss()
        mouseScrollController?.stop()
        screenshotController.cancel()
        pinnedImageManager.closeAll()
        model.endSession()
        clipboardTimer?.invalidate()
        HotKeyManager.shared.unregister()
        scanTask?.cancel()
    }
}
