import AppKit

@MainActor final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    private struct SidebarGroup {
        let titleKey: String
        let items: [(key: String, symbol: String)]
    }

    private static let sidebarGroups: [SidebarGroup] = [
        SidebarGroup(titleKey: "settings.group.basics", items: [
            ("general", "gearshape"),
            ("app_shortcuts", "command"),
        ]),
        SidebarGroup(titleKey: "settings.group.search", items: [
            ("default_results", "sparkle.magnifyingglass"),
            ("file_search", "folder"),
            ("web_search", "globe"),
            ("bookmarks", "bookmark"),
            ("calculator", "plus.forwardslash.minus"),
        ]),
        SidebarGroup(titleKey: "settings.group.tools", items: [
            ("screenshots", "camera.viewfinder"),
            ("mouse", "computermouse"),
            ("image_upload", "icloud.and.arrow.up"),
        ]),
    ]

    static var pageTitles: [String] {
        sidebarGroups.flatMap(\.items).map { L10n.tr("settings.page.\($0.key)") }
    }

    private let store: SettingsStore
    private let usage: UsageStore
    private let bookmarks: BookmarkStore?
    private let applicationsProvider: () -> [AppItem]
    private let setHotKeySuspended: (Bool) -> Void
    private let mousePermissionProvider: () -> (MouseScrollController.RuntimeStatus, Bool)
    private let onRequestMousePermission: () -> Void
    private let onOpenMouseAccessibilitySettings: () -> Bool
    private let onRefreshMousePermission: () -> Void
    private let uploadHistoryProvider: () -> [UploadHistoryItem]
    private let onCopyUploadHistory: (UploadHistoryItem) -> Void
    private let onClearUploadHistory: () -> Void
    private let apply: (LauncherSettings) throws -> Void

    private var activeSettings: LauncherSettings
    let hotKeyRecorder = HotKeyRecorderView(binding: .optionSpace, allowsClearing: false)
    let clipboardHotKeyRecorder = HotKeyRecorderView(binding: .optionCommandC, allowsClearing: false)
    let screenshotHotKeyRecorder = HotKeyRecorderView(binding: .controlOptionP, allowsClearing: true)
    let languagePopup = NSPopUpButton()
    let rememberSwitch = NSSwitch()
    let enginePopup = NSPopUpButton()
    let fallbackPopup = NSPopUpButton()
    let defaultBookmarksSwitch = NSSwitch()

    let appShortcutsSettings = AppShortcutsSettingsView()
    let fileSearchSettings = FileSearchSettingsView()
    let webSearchSettings = WebSearchSettingsView()
    let bookmarksSettings = BookmarksSettingsView()
    let mouseScrollSettings = MouseScrollSettingsView()
    let imageUploadSettings: ImageUploadSettingsView

    private let statusBanner = SettingsStatusBanner()
    private let scrollView = NSScrollView()
    let pageHost = SettingsFlippedView()
    var pages: [String: NSStackView] = [:]
    private var navigation: [SettingsSidebarItemView] = []
    private var pageBottom: NSLayoutConstraint?
    private(set) var selectedPageTitle = L10n.tr("settings.page.general")
    private var bookmarkBusy = false

    init(store: SettingsStore, usage: UsageStore, bookmarks: BookmarkStore? = nil,
         applicationsProvider: @escaping () -> [AppItem] = { [] },
         setHotKeySuspended: @escaping (Bool) -> Void = { _ in },
         mousePermissionProvider: @escaping () -> (MouseScrollController.RuntimeStatus, Bool) = { (.inactive, false) },
         onRequestMousePermission: @escaping () -> Void = {},
         onOpenMouseAccessibilitySettings: @escaping () -> Bool = { false },
         onRefreshMousePermission: @escaping () -> Void = {},
         imageUploadSecretStore: ImageUploadSecretStoring = KeychainSecretStore(),
         uploadHistoryProvider: @escaping () -> [UploadHistoryItem] = { [] },
         onCopyUploadHistory: @escaping (UploadHistoryItem) -> Void = { _ in },
         onClearUploadHistory: @escaping () -> Void = {},
         apply: @escaping (LauncherSettings) throws -> Void) {
        self.store = store
        self.usage = usage
        self.bookmarks = bookmarks
        self.applicationsProvider = applicationsProvider
        self.setHotKeySuspended = setHotKeySuspended
        self.mousePermissionProvider = mousePermissionProvider
        self.onRequestMousePermission = onRequestMousePermission
        self.onOpenMouseAccessibilitySettings = onOpenMouseAccessibilitySettings
        self.onRefreshMousePermission = onRefreshMousePermission
        self.uploadHistoryProvider = uploadHistoryProvider
        self.onCopyUploadHistory = onCopyUploadHistory
        self.onClearUploadHistory = onClearUploadHistory
        self.imageUploadSettings = ImageUploadSettingsView(secretStore: imageUploadSecretStore)
        self.apply = apply
        self.activeSettings = store.settings

        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: SettingsStyle.windowDefaultSize),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = L10n.tr("settings.window_title")
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.minSize = SettingsStyle.windowMinSize
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        configure()
        window.center()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func windowWillClose(_ notification: Notification) {
        if let sheet = window?.attachedSheet {
            window?.endSheet(sheet)
            sheet.orderOut(nil)
        }
        window?.makeFirstResponder(nil)
        setHotKeySuspended(false)
    }

    func reloadApplications(_ apps: [AppItem]) {
        appShortcutsSettings.updateAvailableApps(apps)
    }

    func reloadMouseStatus() {
        let state = mousePermissionProvider()
        mouseScrollSettings.updatePermissionStatus(state.0, isTrusted: state.1)
    }

    func reloadImageUploadHistory() {
        imageUploadSettings.reloadHistory(uploadHistoryProvider())
    }

    override func showWindow(_ sender: Any?) {
        let value = store.settings
        activeSettings = value
        hotKeyRecorder.setBinding(value.hotKey)
        clipboardHotKeyRecorder.setBinding(value.clipboardHotKey)
        screenshotHotKeyRecorder.setBinding(value.screenshotHotKey)
        languagePopup.selectItem(at: AppLanguage.allCases.firstIndex(of: value.language) ?? 0)
        rememberSwitch.state = value.rememberUsage ? .on : .off
        enginePopup.selectItem(at: SearchEngine.allCases.firstIndex(of: value.searchEngine) ?? 0)
        fallbackPopup.selectItem(at: value.fallbackOnlyWhenNoResults ? 1 : 0)

        appShortcutsSettings.reload(value.appShortcuts, availableApps: applicationsProvider())
        fileSearchSettings.reload(value.searchDirectories)
        webSearchSettings.reload(value.webSearches)
        let mouseState = mousePermissionProvider()
        mouseScrollSettings.reload(value.mouseScroll, status: mouseState.0, isTrusted: mouseState.1)
        imageUploadSettings.reload(value.imageUpload, history: uploadHistoryProvider())

        if let warning = store.warning {
            statusBanner.show(warning, level: .warning)
        } else {
            statusBanner.clear()
        }
        super.showWindow(sender)
        reloadBookmarks()
    }

    func selectPage(_ title: String) {
        guard let selected = pages[title] else { return }
        selectedPageTitle = title
        pageBottom?.isActive = false
        for (name, page) in pages {
            page.isHidden = name != title
        }
        for button in navigation {
            button.state = button.title == title ? .on : .off
        }
        pageBottom = pageHost.bottomAnchor.constraint(equalTo: selected.bottomAnchor, constant: SettingsStyle.contentBottomPadding)
        pageBottom?.isActive = true
        scrollView.contentView.scroll(to: .zero)
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    // MARK: - Shell Configuration

    private func configure() {
        guard let content = window?.contentView else { return }
        wireControlCallbacks()

        let sidebar = buildSidebar()
        let verticalDivider = SettingsHairlineView(vertical: true)
        let canvas = SettingsCanvasView()
        canvas.translatesAutoresizingMaskIntoConstraints = false

        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.automaticallyAdjustsContentInsets = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        pageHost.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = pageHost

        let bannerHost = NSView()
        bannerHost.translatesAutoresizingMaskIntoConstraints = false
        bannerHost.addSubview(statusBanner)
        NSLayoutConstraint.activate([
            statusBanner.leadingAnchor.constraint(equalTo: bannerHost.leadingAnchor, constant: SettingsStyle.contentHorizontalPadding),
            statusBanner.trailingAnchor.constraint(equalTo: bannerHost.trailingAnchor, constant: -SettingsStyle.contentHorizontalPadding),
            statusBanner.topAnchor.constraint(equalTo: bannerHost.topAnchor, constant: 26),
            statusBanner.bottomAnchor.constraint(equalTo: bannerHost.bottomAnchor),
        ])

        let rightStack = NSStackView(views: [bannerHost, scrollView])
        rightStack.orientation = .vertical
        rightStack.alignment = .leading
        rightStack.spacing = 0
        rightStack.translatesAutoresizingMaskIntoConstraints = false
        canvas.addSubview(rightStack)

        content.addSubview(sidebar)
        content.addSubview(verticalDivider)
        content.addSubview(canvas)

        NSLayoutConstraint.activate([
            sidebar.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            sidebar.topAnchor.constraint(equalTo: content.topAnchor),
            sidebar.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            sidebar.widthAnchor.constraint(equalToConstant: SettingsStyle.sidebarWidth),

            verticalDivider.leadingAnchor.constraint(equalTo: sidebar.trailingAnchor),
            verticalDivider.topAnchor.constraint(equalTo: content.topAnchor),
            verticalDivider.bottomAnchor.constraint(equalTo: content.bottomAnchor),

            canvas.leadingAnchor.constraint(equalTo: verticalDivider.trailingAnchor),
            canvas.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            canvas.topAnchor.constraint(equalTo: content.topAnchor),
            canvas.bottomAnchor.constraint(equalTo: content.bottomAnchor),

            rightStack.leadingAnchor.constraint(equalTo: canvas.leadingAnchor),
            rightStack.trailingAnchor.constraint(equalTo: canvas.trailingAnchor),
            rightStack.topAnchor.constraint(equalTo: canvas.topAnchor),
            rightStack.bottomAnchor.constraint(equalTo: canvas.bottomAnchor),
            bannerHost.widthAnchor.constraint(equalTo: rightStack.widthAnchor),
            scrollView.widthAnchor.constraint(equalTo: rightStack.widthAnchor),
            pageHost.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor),
        ])

        bannerHost.isHidden = true
        statusBanner.onVisibilityChanged = { [weak bannerHost] visible in
            bannerHost?.isHidden = !visible
        }

        buildPages()
        selectPage(L10n.tr("settings.page.general"))
    }

    private func buildSidebar() -> NSView {
        let sidebar = NSVisualEffectView()
        sidebar.material = .sidebar
        sidebar.blendingMode = .behindWindow
        sidebar.translatesAutoresizingMaskIntoConstraints = false

        let navStack = NSStackView()
        navStack.orientation = .vertical
        navStack.alignment = .leading
        navStack.spacing = 2
        navStack.translatesAutoresizingMaskIntoConstraints = false

        for (groupIndex, group) in Self.sidebarGroups.enumerated() {
            let groupHeader = NSTextField(labelWithString: L10n.tr(group.titleKey))
            groupHeader.font = SettingsStyle.sidebarGroupFont
            groupHeader.textColor = SettingsStyle.sidebarGroupText
            groupHeader.translatesAutoresizingMaskIntoConstraints = false

            let headerWrapper = NSView()
            headerWrapper.translatesAutoresizingMaskIntoConstraints = false
            headerWrapper.addSubview(groupHeader)
            NSLayoutConstraint.activate([
                groupHeader.leadingAnchor.constraint(equalTo: headerWrapper.leadingAnchor, constant: 10),
                groupHeader.trailingAnchor.constraint(equalTo: headerWrapper.trailingAnchor, constant: -10),
                groupHeader.topAnchor.constraint(equalTo: headerWrapper.topAnchor, constant: groupIndex == 0 ? 0 : 12),
                groupHeader.bottomAnchor.constraint(equalTo: headerWrapper.bottomAnchor, constant: -4),
            ])
            navStack.addArrangedSubview(headerWrapper)
            headerWrapper.widthAnchor.constraint(equalTo: navStack.widthAnchor).isActive = true

            for item in group.items {
                let title = L10n.tr("settings.page.\(item.key)")
                let button = SettingsSidebarItemView(
                    title: title,
                    symbolName: item.symbol,
                    target: self,
                    action: #selector(navigate(_:))
                )
                navigation.append(button)
                navStack.addArrangedSubview(button)
                button.widthAnchor.constraint(equalTo: navStack.widthAnchor).isActive = true
            }
        }

        sidebar.addSubview(navStack)
        NSLayoutConstraint.activate([
            navStack.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor, constant: 12),
            navStack.trailingAnchor.constraint(equalTo: sidebar.trailingAnchor, constant: -12),
            navStack.topAnchor.constraint(equalTo: sidebar.topAnchor, constant: SettingsStyle.sidebarTopInset),
        ])
        return sidebar
    }

    private func wireControlCallbacks() {
        hotKeyRecorder.setAccessibilityLabel(L10n.tr("settings.hotkey"))
        clipboardHotKeyRecorder.setAccessibilityLabel(L10n.tr("settings.clipboard_hotkey"))
        screenshotHotKeyRecorder.setAccessibilityLabel(L10n.tr("settings.screenshot_hotkey"))
        hotKeyRecorder.onRecordingStateChanged = setHotKeySuspended
        clipboardHotKeyRecorder.onRecordingStateChanged = setHotKeySuspended
        screenshotHotKeyRecorder.onRecordingStateChanged = setHotKeySuspended
        appShortcutsSettings.onRecordingStateChanged = setHotKeySuspended
        imageUploadSettings.onRecordingStateChanged = setHotKeySuspended

        hotKeyRecorder.onChange = { [weak self] binding in
            guard let self, let binding else { return }
            let previous = self.activeSettings.hotKey
            let result = self.commitSettings({ $0.updating(hotKey: binding) })
            if case .failure = result { self.hotKeyRecorder.setBinding(previous) }
        }
        clipboardHotKeyRecorder.onChange = { [weak self] binding in
            guard let self, let binding else { return }
            let previous = self.activeSettings.clipboardHotKey
            let result = self.commitSettings({ $0.updating(clipboardHotKey: binding) })
            if case .failure = result { self.clipboardHotKeyRecorder.setBinding(previous) }
        }
        screenshotHotKeyRecorder.onChange = { [weak self] binding in
            guard let self else { return }
            let previous = self.activeSettings.screenshotHotKey
            let result = self.commitSettings({ $0.updating(screenshotHotKey: .some(binding)) })
            if case .failure = result { self.screenshotHotKeyRecorder.setBinding(previous) }
        }

        languagePopup.addItems(withTitles: AppLanguage.allCases.map(\.title))
        languagePopup.target = self
        languagePopup.action = #selector(languageChanged)
        languagePopup.setAccessibilityLabel(L10n.tr("settings.language"))
        languagePopup.widthAnchor.constraint(equalToConstant: 150).isActive = true

        rememberSwitch.controlSize = .small
        rememberSwitch.target = self
        rememberSwitch.action = #selector(rememberUsageChanged)
        rememberSwitch.setAccessibilityLabel(L10n.tr("settings.remember_usage"))

        enginePopup.addItems(withTitles: SearchEngine.allCases.map(\.title))
        enginePopup.target = self
        enginePopup.action = #selector(searchEngineChanged)
        enginePopup.setAccessibilityLabel(L10n.tr("settings.search_engine"))
        enginePopup.widthAnchor.constraint(equalToConstant: 150).isActive = true

        fallbackPopup.addItems(withTitles: [L10n.tr("settings.fallback.always"), L10n.tr("settings.fallback.no_results")])
        fallbackPopup.target = self
        fallbackPopup.action = #selector(fallbackChanged)
        fallbackPopup.setAccessibilityLabel(L10n.tr("settings.web_fallback"))
        fallbackPopup.widthAnchor.constraint(equalToConstant: 210).isActive = true

        defaultBookmarksSwitch.controlSize = .small
        defaultBookmarksSwitch.target = self
        defaultBookmarksSwitch.action = #selector(defaultBookmarksToggled)
        defaultBookmarksSwitch.setAccessibilityLabel(L10n.tr("settings.bookmarks.default_accessibility"))

        appShortcutsSettings.onCommitShortcuts = { [weak self] updated in
            guard let self else { return .success(()) }
            let isSheetActive = self.window?.attachedSheet != nil
            return self.commitSettings(
                { $0.updating(appShortcuts: updated) },
                showInlineError: !isSheetActive
            )
        }

        fileSearchSettings.onAddRequested = { [weak self] in
            self?.addDirectory()
        }
        fileSearchSettings.onRemoveDirectory = { [weak self] path in
            self?.removeDirectory(path)
        }

        webSearchSettings.onCommitDefinitions = { [weak self] updated in
            guard let self else { return .success(()) }
            let isSheetActive = self.window?.attachedSheet != nil
            return self.commitSettings(
                { $0.updating(webSearches: updated) },
                showInlineError: !isSheetActive
            )
        }

        bookmarksSettings.onPreferenceChanged = { [weak self] prefs in
            self?.saveBookmarkPreferences(prefs)
        }
        bookmarksSettings.onProfileToggled = { [weak self] id, selected in
            self?.toggleBookmarkProfile(id: id, selected: selected)
        }
        bookmarksSettings.onDetectProfiles = { [weak self] in self?.detectProfiles() }
        bookmarksSettings.onChooseDirectory = { [weak self] in self?.chooseChromeDirectory() }
        bookmarksSettings.onRefreshBookmarks = { [weak self] in self?.refreshBookmarks() }
        bookmarksSettings.onClearBookmarks = { [weak self] in self?.clearBookmarks() }

        mouseScrollSettings.onRequestPermission = { [weak self] in
            self?.onRequestMousePermission()
            self?.reloadMouseStatus()
        }
        mouseScrollSettings.onOpenAccessibilitySettings = { [weak self] in
            guard let self else { return false }
            let opened = self.onOpenMouseAccessibilitySettings()
            if !opened {
                self.statusBanner.show(L10n.tr("mouse.permission.settings_failed"), level: .error)
            }
            return opened
        }
        mouseScrollSettings.onRefreshPermission = { [weak self] in
            self?.onRefreshMousePermission()
            self?.reloadMouseStatus()
        }
        mouseScrollSettings.onCommitSettings = { [weak self] updated in
            guard let self else { return .success(()) }
            let result = self.commitSettings({ $0.updating(mouseScroll: updated) })
            if case .success = result { self.reloadMouseStatus() }
            return result
        }

        imageUploadSettings.onCommitSettings = { [weak self] updated, afterApply in
            guard let self else { return .success(()) }
            let isSheetActive = self.window?.attachedSheet != nil
            return self.commitSettings(
                { $0.updating(imageUpload: updated) },
                afterApply: afterApply,
                showInlineError: !isSheetActive
            )
        }
        imageUploadSettings.onCopyHistoryItem = { [weak self] item in
            self?.onCopyUploadHistory(item)
            self?.statusBanner.show(L10n.tr("image_upload.history.copied_feedback"), level: .success)
        }
        imageUploadSettings.onClearHistory = { [weak self] in
            self?.onClearUploadHistory()
            self?.reloadImageUploadHistory()
        }
    }

    // MARK: - Instant-Apply Commit Pipeline

    @discardableResult
    private func commitSettings(
        _ transform: (LauncherSettings) -> LauncherSettings,
        afterApply: (() throws -> Void)? = nil,
        showInlineError: Bool = true
    ) -> Result<Void, Error> {
        let next = transform(activeSettings)
        let languageChanged = next.language != activeSettings.language
        do {
            try apply(next)
            try afterApply?()
            activeSettings = next
            if languageChanged {
                statusBanner.show(L10n.tr("settings.restart_required"), level: .warning)
            } else {
                statusBanner.clear()
            }
            return .success(())
        } catch {
            if showInlineError {
                statusBanner.show(error.localizedDescription, level: .error)
            }
            return .failure(error)
        }
    }

    // MARK: - Actions

    @objc private func navigate(_ sender: NSButton) { selectPage(sender.title) }
    @objc func openBookmarks() { selectPage(L10n.tr("settings.page.bookmarks")) }

    @objc private func languageChanged() {
        let index = max(0, min(AppLanguage.allCases.count - 1, languagePopup.indexOfSelectedItem))
        let previous = activeSettings.language
        let nextLanguage = AppLanguage.allCases[index]
        let result = commitSettings({ $0.updating(language: nextLanguage) })
        if case .failure = result {
            languagePopup.selectItem(at: AppLanguage.allCases.firstIndex(of: previous) ?? 0)
        }
    }

    @objc private func rememberUsageChanged() {
        let previous = activeSettings.rememberUsage
        let result = commitSettings({ $0.updating(rememberUsage: rememberSwitch.state == .on) })
        if case .failure = result {
            rememberSwitch.state = previous ? .on : .off
        }
    }

    @objc private func searchEngineChanged() {
        let index = max(0, min(SearchEngine.allCases.count - 1, enginePopup.indexOfSelectedItem))
        let previous = activeSettings.searchEngine
        let nextEngine = SearchEngine.allCases[index]
        let result = commitSettings({ $0.updating(searchEngine: nextEngine) })
        if case .failure = result {
            enginePopup.selectItem(at: SearchEngine.allCases.firstIndex(of: previous) ?? 0)
        }
    }

    @objc private func fallbackChanged() {
        let previous = activeSettings.fallbackOnlyWhenNoResults
        let nextFallback = fallbackPopup.indexOfSelectedItem == 1
        let result = commitSettings({ $0.updating(fallbackOnlyWhenNoResults: nextFallback) })
        if case .failure = result {
            fallbackPopup.selectItem(at: previous ? 1 : 0)
        }
    }

    @objc func clearHistory() {
        usage.clear()
        statusBanner.show(L10n.tr("settings.usage_cleared"), level: .success)
    }

    @objc func addDirectory() {
        guard let window else { return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.prompt = L10n.tr("common.add")
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let self else { return }
            let added = panel.urls.map { $0.standardizedFileURL.path }
            let updated = Array(Set(self.activeSettings.searchDirectories + added)).sorted()
            if case .success = self.commitSettings({ $0.updating(searchDirectories: updated) }) {
                self.fileSearchSettings.reload(updated)
            }
        }
    }

    private func removeDirectory(_ path: String) {
        let updated = activeSettings.searchDirectories.filter { $0 != path }
        if case .success = commitSettings({ $0.updating(searchDirectories: updated) }) {
            fileSearchSettings.reload(updated)
        }
    }

    // MARK: - Bookmarks

    private func reloadBookmarks() {
        let prefs = bookmarks?.preferences ?? BookmarkPreferences()
        defaultBookmarksSwitch.state = prefs.includeInDefaultResults ? .on : .off
        defaultBookmarksSwitch.isEnabled = bookmarks != nil && !bookmarkBusy
        bookmarksSettings.reload(bookmarks: bookmarks, busy: bookmarkBusy)
    }

    @objc private func defaultBookmarksToggled() {
        guard let bookmarks else { return }
        var prefs = bookmarks.preferences
        prefs.includeInDefaultResults = defaultBookmarksSwitch.state == .on
        saveBookmarkPreferences(prefs)
    }

    private func saveBookmarkPreferences(_ prefs: BookmarkPreferences) {
        guard let bookmarks else { return }
        do {
            try bookmarks.updatePreferences(prefs)
            statusBanner.clear()
        } catch {
            statusBanner.show(error.localizedDescription, level: .error)
        }
        reloadBookmarks()
    }

    private func toggleBookmarkProfile(id: String, selected: Bool) {
        guard let bookmarks else { return }
        do {
            try bookmarks.setSelected(selected, profileID: id)
            statusBanner.clear()
        } catch {
            statusBanner.show(error.localizedDescription, level: .error)
        }
        reloadBookmarks()
    }

    private func runBookmarkOperation(_ operation: @escaping @MainActor (BookmarkStore) async throws -> Void) {
        guard let bookmarks, !bookmarkBusy else { return }
        bookmarkBusy = true
        reloadBookmarks()
        Task { [weak self] in
            do {
                try await operation(bookmarks)
                self?.statusBanner.show(L10n.tr("settings.bookmarks.operation_succeeded"), level: .success)
            } catch {
                self?.statusBanner.show(L10n.format("settings.bookmarks.operation_failed", error.localizedDescription), level: .error)
            }
            self?.bookmarkBusy = false
            self?.reloadBookmarks()
        }
    }

    private func detectProfiles() {
        runBookmarkOperation { try await $0.discoverProfiles(root: BookmarkStore.defaultChromeRoot) }
    }

    private func refreshBookmarks() {
        runBookmarkOperation { try await $0.refreshSelected() }
    }

    private func chooseChromeDirectory() {
        guard let window else { return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.message = L10n.tr("settings.bookmarks.choose_message")
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.runBookmarkOperation { try await $0.discoverProfiles(root: url) }
        }
    }

    private func clearBookmarks() {
        guard let window, let bookmarks else { return }
        let alert = NSAlert()
        alert.messageText = L10n.tr("settings.bookmarks.clear_title")
        alert.informativeText = L10n.tr("settings.bookmarks.clear_message")
        alert.addButton(withTitle: L10n.tr("common.cancel"))
        alert.addButton(withTitle: L10n.tr("common.clear"))
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertSecondButtonReturn else { return }
            do {
                try bookmarks.clearImportedData()
                self?.statusBanner.show(L10n.tr("settings.bookmarks.cleared"), level: .success)
            } catch {
                self?.statusBanner.show(error.localizedDescription, level: .error)
            }
            self?.reloadBookmarks()
        }
    }
}

// MARK: - Immutable LauncherSettings Copy Helper

private extension LauncherSettings {
    func updating(
        hotKey: HotKeyPreset? = nil,
        searchDirectories: [String]? = nil,
        searchEngine: SearchEngine? = nil,
        rememberUsage: Bool? = nil,
        webSearches: [WebSearchDefinition]? = nil,
        fallbackOnlyWhenNoResults: Bool? = nil,
        clipboardHotKey: HotKeyPreset? = nil,
        language: AppLanguage? = nil,
        screenshotHotKey: HotKeyPreset?? = nil,
        appShortcuts: [AppShortcut]? = nil,
        mouseScroll: MouseScrollSettings? = nil,
        imageUpload: ImageUploadSettings? = nil
    ) -> LauncherSettings {
        LauncherSettings(
            hotKey: hotKey ?? self.hotKey,
            searchDirectories: searchDirectories ?? self.searchDirectories,
            searchEngine: searchEngine ?? self.searchEngine,
            rememberUsage: rememberUsage ?? self.rememberUsage,
            webSearches: webSearches ?? self.webSearches,
            fallbackOnlyWhenNoResults: fallbackOnlyWhenNoResults ?? self.fallbackOnlyWhenNoResults,
            clipboardHotKey: clipboardHotKey ?? self.clipboardHotKey,
            language: language ?? self.language,
            screenshotHotKey: screenshotHotKey ?? self.screenshotHotKey,
            appShortcuts: appShortcuts ?? self.appShortcuts,
            mouseScroll: mouseScroll ?? self.mouseScroll,
            imageUpload: imageUpload ?? self.imageUpload
        )
    }
}
