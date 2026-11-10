import AppKit

private final class SettingsPageHost: NSView {
    override var isFlipped: Bool { true }
}

@MainActor final class SettingsWindowController: NSWindowController {
    static var pageTitles: [String] {
        ["general", "default_results", "file_search", "web_search", "bookmarks", "calculator"].map {
            L10n.tr("settings.page.\($0)")
        }
    }
    private let store: SettingsStore
    private let usage: UsageStore
    private let bookmarks: BookmarkStore?
    private let apply: (LauncherSettings) throws -> Void
    private let hotKeyRecorder = HotKeyRecorderView(binding: .optionSpace)
    private let clipboardHotKeyRecorder = HotKeyRecorderView(binding: .optionCommandC)
    private let engine = NSPopUpButton()
    private let languagePopup = NSPopUpButton()
    private let webSearchSettings = WebSearchSettingsView()
    private let fallback = NSPopUpButton()
    private let remember = NSButton(checkboxWithTitle: L10n.tr("settings.remember_usage"), target: nil, action: nil)
    private let directories = NSPopUpButton()
    private let feedback = NSTextField(wrappingLabelWithString: "")
    private let pageHost = SettingsPageHost()
    private var pages: [String: NSStackView] = [:]
    private var navigation: [NSButton] = []
    private var pageBottom: NSLayoutConstraint?
    private var paths: [String] = []
    private(set) var selectedPageTitle = L10n.tr("settings.page.general")
    private let bookmarkEnabled = NSButton(checkboxWithTitle: L10n.tr("settings.bookmarks.enabled"), target: nil, action: nil)
    private let defaultBookmarks = NSButton(checkboxWithTitle: L10n.tr("settings.page.bookmarks"), target: nil, action: nil)
    private let bookmarkInDefault = NSButton(checkboxWithTitle: L10n.tr("settings.bookmarks.include_default"), target: nil, action: nil)
    private let matchTitle = NSButton(checkboxWithTitle: L10n.tr("settings.bookmarks.match_title"), target: nil, action: nil)
    private let matchURL = NSButton(checkboxWithTitle: L10n.tr("settings.bookmarks.match_url"), target: nil, action: nil)
    private let matchFolders = NSButton(checkboxWithTitle: L10n.tr("settings.bookmarks.match_folders"), target: nil, action: nil)
    private let profileList = NSStackView()
    private let bookmarkStatus = NSTextField(wrappingLabelWithString: L10n.tr("settings.bookmarks.not_imported"))
    private var bookmarkButtons: [NSButton] = []
    private var bookmarkBusy = false

    init(store: SettingsStore, usage: UsageStore, bookmarks: BookmarkStore? = nil,
         apply: @escaping (LauncherSettings) throws -> Void) {
        self.store = store
        self.usage = usage
        self.bookmarks = bookmarks
        self.apply = apply
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 640),
                              styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = L10n.tr("settings.window_title")
        window.minSize = NSSize(width: 780, height: 580)
        window.isReleasedWhenClosed = false
        super.init(window: window)
        configure()
        window.center()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func showWindow(_ sender: Any?) {
        let value = store.settings
        hotKeyRecorder.setBinding(value.hotKey)
        clipboardHotKeyRecorder.setBinding(value.clipboardHotKey)
        engine.selectItem(at: SearchEngine.allCases.firstIndex(of: value.searchEngine) ?? 0)
        languagePopup.selectItem(at: AppLanguage.allCases.firstIndex(of: value.language) ?? 0)
        webSearchSettings.reload(value.webSearches)
        fallback.selectItem(at: value.fallbackOnlyWhenNoResults ? 1 : 0)
        remember.state = value.rememberUsage ? .on : .off
        paths = value.searchDirectories
        reloadDirectories()
        feedback.stringValue = store.warning ?? L10n.tr("settings.save_help")
        super.showWindow(sender)
        reloadBookmarks()
    }

    private func configure() {
        guard let content = window?.contentView else { return }
        hotKeyRecorder.setAccessibilityLabel(L10n.tr("settings.hotkey"))
        clipboardHotKeyRecorder.setAccessibilityLabel(L10n.tr("settings.clipboard_hotkey"))
        engine.addItems(withTitles: SearchEngine.allCases.map(\.title))
        languagePopup.addItems(withTitles: AppLanguage.allCases.map(\.title))
        languagePopup.setAccessibilityLabel(L10n.tr("settings.language"))
        fallback.addItems(withTitles: [L10n.tr("settings.fallback.always"), L10n.tr("settings.fallback.no_results")])
        engine.setAccessibilityLabel(L10n.tr("settings.search_engine"))
        fallback.setAccessibilityLabel(L10n.tr("settings.web_fallback"))
        directories.setAccessibilityLabel(L10n.tr("settings.search_directories"))
        directories.widthAnchor.constraint(equalToConstant: 320).isActive = true
        feedback.font = .systemFont(ofSize: 12)
        feedback.textColor = .secondaryLabelColor

        let sidebar = NSVisualEffectView()
        sidebar.material = .sidebar
        sidebar.blendingMode = .behindWindow
        sidebar.translatesAutoresizingMaskIntoConstraints = false
        let nav = NSStackView()
        nav.orientation = .vertical
        nav.alignment = .leading
        nav.spacing = 6
        nav.translatesAutoresizingMaskIntoConstraints = false
        let symbols = ["gearshape", "list.bullet", "folder", "globe", "bookmark", "plus.forwardslash.minus"]
        for (index, title) in Self.pageTitles.enumerated() {
            let button = NSButton(title: title, target: self, action: #selector(navigate(_:)))
            button.setButtonType(.pushOnPushOff)
            button.bezelStyle = .recessed
            button.alignment = .left
            button.image = NSImage(systemSymbolName: symbols[index], accessibilityDescription: nil)
            button.imagePosition = .imageLeading
            button.setAccessibilityLabel(L10n.format("settings.page_accessibility", title))
            button.widthAnchor.constraint(equalToConstant: 156).isActive = true
            button.heightAnchor.constraint(equalToConstant: 36).isActive = true
            navigation.append(button)
            nav.addArrangedSubview(button)
        }
        sidebar.addSubview(nav)
        content.addSubview(sidebar)
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        pageHost.translatesAutoresizingMaskIntoConstraints = false
        scroll.documentView = pageHost
        content.addSubview(scroll)
        let save = NSButton(title: L10n.tr("settings.save"), target: self, action: #selector(saveSettings))
        save.keyEquivalent = "\r"
        let footer = NSStackView(views: [feedback, save])
        footer.spacing = 16
        footer.translatesAutoresizingMaskIntoConstraints = false
        feedback.setContentHuggingPriority(.defaultLow, for: .horizontal)
        content.addSubview(footer)
        NSLayoutConstraint.activate([
            sidebar.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            sidebar.topAnchor.constraint(equalTo: content.topAnchor),
            sidebar.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            sidebar.widthAnchor.constraint(equalToConstant: 184),
            nav.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor, constant: 14),
            nav.topAnchor.constraint(equalTo: sidebar.topAnchor, constant: 22),
            scroll.leadingAnchor.constraint(equalTo: sidebar.trailingAnchor),
            scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: content.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: footer.topAnchor, constant: -16),
            pageHost.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
            footer.leadingAnchor.constraint(equalTo: sidebar.trailingAnchor, constant: 28),
            footer.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -28),
            footer.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -18),
        ])
        buildPages()
        selectPage(L10n.tr("settings.page.general"))
    }

    private func buildPages() {
        addPage(L10n.tr("settings.page.general"), description: L10n.tr("settings.general.description"), controls: [
            row(L10n.tr("settings.language"), languagePopup),
            row(L10n.tr("settings.hotkey"), hotKeyRecorder),
            row(L10n.tr("settings.clipboard_hotkey"), clipboardHotKeyRecorder),
            remember,
            NSButton(title: L10n.tr("settings.clear_usage"), target: self, action: #selector(clearHistory)),
        ])
        defaultBookmarks.target = self
        defaultBookmarks.action = #selector(bookmarkPreferenceChanged(_:))
        defaultBookmarks.setAccessibilityLabel(L10n.tr("settings.bookmarks.default_accessibility"))
        bookmarkInDefault.setAccessibilityLabel(L10n.tr("settings.bookmarks.default_accessibility"))
        let bookmarkLink = NSButton(title: L10n.tr("settings.bookmarks.configure"), target: self, action: #selector(openBookmarks))
        addPage(L10n.tr("settings.page.default_results"), description: L10n.tr("settings.default_results.description"), controls: [
            note(L10n.tr("settings.default_results.note")),
            NSStackView(views: [defaultBookmarks, bookmarkLink]),
            note(L10n.tr("settings.default_results.bookmarks_note")),
            row(L10n.tr("settings.web_fallback"), fallback),
        ])
        addPage(L10n.tr("settings.page.file_search"), description: L10n.tr("settings.file_search.description"), controls: [
            row(L10n.tr("settings.search_directories"), directories),
            NSStackView(views: [NSButton(title: L10n.tr("settings.add_directory"), target: self, action: #selector(addDirectory)),
                               NSButton(title: L10n.tr("settings.remove_directory"), target: self, action: #selector(removeDirectory))]),
            note(L10n.tr("settings.file_search.spotlight_note")),
            note(L10n.tr("settings.file_search.commands_note")),
        ])
        addPage(L10n.tr("settings.page.web_search"), description: L10n.tr("settings.web_search.description"), controls: [
            row(L10n.tr("settings.search_engine"), engine),
            webSearchSettings,
            note(L10n.tr("settings.web_search.note")),
        ])
        if let page = pages[L10n.tr("settings.page.web_search")] {
            webSearchSettings.widthAnchor.constraint(equalTo: page.widthAnchor).isActive = true
        }
        for button in [bookmarkEnabled, bookmarkInDefault, matchTitle, matchURL, matchFolders] {
            button.target = self
            button.action = #selector(bookmarkPreferenceChanged(_:))
        }
        profileList.orientation = .vertical
        profileList.alignment = .leading
        profileList.spacing = 8
        let detect = NSButton(title: L10n.tr("settings.bookmarks.detect"), target: self, action: #selector(detectProfiles))
        let choose = NSButton(title: L10n.tr("settings.bookmarks.choose_directory"), target: self, action: #selector(chooseChromeDirectory))
        let refresh = NSButton(title: L10n.tr("settings.bookmarks.import_refresh"), target: self, action: #selector(refreshBookmarks))
        let clear = NSButton(title: L10n.tr("settings.bookmarks.clear"), target: self, action: #selector(clearBookmarks))
        bookmarkButtons = [detect, choose, refresh, clear]
        bookmarkStatus.font = .systemFont(ofSize: 12)
        bookmarkStatus.textColor = .secondaryLabelColor
        addPage(L10n.tr("settings.page.bookmarks"), description: L10n.tr("settings.bookmarks.description"), controls: [
            bookmarkEnabled, row(L10n.tr("settings.bookmarks.profiles"), profileList),
            NSStackView(views: [detect, choose]), refresh, bookmarkStatus,
            bookmarkInDefault, row(L10n.tr("settings.bookmarks.keyword"), NSTextField(labelWithString: "bm")),
            row(L10n.tr("settings.bookmarks.match_scope"), NSStackView(views: [matchTitle, matchURL, matchFolders])),
            row(L10n.tr("settings.bookmarks.open_with"), NSTextField(labelWithString: L10n.tr("settings.bookmarks.default_browser"))),
            clear, note(L10n.tr("settings.bookmarks.note")),
        ])
        addPage(L10n.tr("settings.page.calculator"), description: L10n.tr("settings.calculator.description"), controls: [
            note(L10n.tr("settings.calculator.syntax_note")),
            note(L10n.tr("settings.calculator.example_note")),
        ])
        // Bookmark state is loaded after the window is first presented.
    }

    private func addPage(_ title: String, description: String, controls: [NSView]) {
        let heading = NSTextField(labelWithString: title)
        heading.font = .systemFont(ofSize: 25, weight: .semibold)
        let separator = NSBox()
        separator.boxType = .separator
        let stack = NSStackView(views: [heading, note(description), separator] + controls)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 18
        stack.translatesAutoresizingMaskIntoConstraints = false
        pageHost.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: pageHost.leadingAnchor, constant: 28),
            stack.trailingAnchor.constraint(equalTo: pageHost.trailingAnchor, constant: -28),
            stack.topAnchor.constraint(equalTo: pageHost.topAnchor, constant: 28),
            separator.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])
        for view in stack.arrangedSubviews where view is NSTextField {
            view.widthAnchor.constraint(lessThanOrEqualTo: stack.widthAnchor).isActive = true
        }
        if title == L10n.tr("settings.page.bookmarks") {
            bookmarkStatus.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
            profileList.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -128).isActive = true
        }
        pages[title] = stack
    }

    func selectPage(_ title: String) {
        guard let selected = pages[title] else { return }
        selectedPageTitle = title
        pageBottom?.isActive = false
        for (name, page) in pages { page.isHidden = name != title }
        for button in navigation { button.state = button.title == title ? .on : .off }
        pageBottom = pageHost.bottomAnchor.constraint(equalTo: selected.bottomAnchor, constant: 28)
        pageBottom?.isActive = true
        selected.scrollToVisible(selected.bounds)
    }

    @objc private func navigate(_ sender: NSButton) { selectPage(sender.title) }
    @objc private func openBookmarks() { selectPage(L10n.tr("settings.page.bookmarks")) }

    private func row(_ title: String, _ control: NSView) -> NSView {
        let label = NSTextField(labelWithString: title)
        label.widthAnchor.constraint(equalToConstant: 116).isActive = true
        let stack = NSStackView(views: [label, control])
        stack.alignment = .top
        stack.spacing = 12
        return stack
    }

    private func note(_ text: String) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = .systemFont(ofSize: 12)
        label.textColor = .secondaryLabelColor
        return label
    }

    private func reloadDirectories() {
        directories.removeAllItems()
        directories.addItems(withTitles: paths.isEmpty ? [L10n.tr("settings.no_directories")] : paths)
    }

    private func reloadBookmarks() {
        let prefs = bookmarks?.preferences ?? BookmarkPreferences()
        bookmarkEnabled.state = prefs.enabled ? .on : .off
        defaultBookmarks.state = prefs.includeInDefaultResults ? .on : .off
        bookmarkInDefault.state = defaultBookmarks.state
        matchTitle.state = prefs.matchTitle ? .on : .off
        matchURL.state = prefs.matchURL ? .on : .off
        matchFolders.state = prefs.matchFolders ? .on : .off
        for control in [bookmarkEnabled, defaultBookmarks, bookmarkInDefault, matchTitle, matchURL, matchFolders] + bookmarkButtons {
            control.isEnabled = bookmarks != nil && !bookmarkBusy
        }
        for view in profileList.arrangedSubviews { profileList.removeArrangedSubview(view); view.removeFromSuperview() }
        guard let bookmarks else {
            profileList.addArrangedSubview(note(L10n.tr("settings.bookmarks.unavailable")))
            return
        }
        if bookmarks.profiles.isEmpty { profileList.addArrangedSubview(note(L10n.tr("settings.bookmarks.not_detected"))) }
        for profile in bookmarks.profiles {
            let count = bookmarks.snapshots[profile.id]?.entries.count
            let status = count.map { L10n.format("settings.bookmarks.imported_count", $0) } ?? L10n.tr("settings.bookmarks.profile_not_imported")
            let button = NSButton(checkboxWithTitle: "\(profile.name) · \(status)",
                                  target: self, action: #selector(profileChanged(_:)))
            button.identifier = NSUserInterfaceItemIdentifier(profile.id)
            button.toolTip = "\(profile.name)\n\(profile.id)"
            button.cell?.lineBreakMode = .byTruncatingMiddle
            button.state = profile.selected ? .on : .off
            button.isEnabled = !bookmarkBusy
            profileList.addArrangedSubview(button)
            button.widthAnchor.constraint(equalTo: profileList.widthAnchor).isActive = true
        }
        let snapshots = bookmarks.snapshots.values
        if bookmarkBusy {
            bookmarkStatus.stringValue = L10n.tr("settings.bookmarks.reading")
        } else if let date = snapshots.map(\.importedAt).max() {
            let imported = snapshots.reduce(0) { $0 + $1.entries.count }
            let skipped = snapshots.reduce(0) { $0 + $1.skippedCount }
            bookmarkStatus.stringValue = L10n.format("settings.bookmarks.import_status",
                                                      date.formatted(date: .abbreviated, time: .shortened), imported, skipped)
        } else {
            bookmarkStatus.stringValue = L10n.tr("settings.bookmarks.import_help")
        }
        if let warning = bookmarks.warning { bookmarkStatus.stringValue += "\n\(warning)" }
    }

    @objc private func bookmarkPreferenceChanged(_ sender: NSButton) {
        guard let bookmarks else { return }
        var prefs = bookmarks.preferences
        if sender === defaultBookmarks || sender === bookmarkInDefault { prefs.includeInDefaultResults = sender.state == .on }
        else if sender === bookmarkEnabled { prefs.enabled = sender.state == .on }
        else if sender === matchTitle { prefs.matchTitle = sender.state == .on }
        else if sender === matchURL { prefs.matchURL = sender.state == .on }
        else if sender === matchFolders { prefs.matchFolders = sender.state == .on }
        do {
            try bookmarks.updatePreferences(prefs)
            feedback.stringValue = L10n.tr("settings.bookmarks.preference_saved")
        } catch { feedback.stringValue = error.localizedDescription }
        reloadBookmarks()
    }

    @objc private func profileChanged(_ sender: NSButton) {
        guard let bookmarks, let id = sender.identifier?.rawValue else { return }
        do { try bookmarks.setSelected(sender.state == .on, profileID: id) }
        catch { feedback.stringValue = error.localizedDescription }
        reloadBookmarks()
    }

    private func runBookmarkOperation(_ operation: @escaping @MainActor (BookmarkStore) async throws -> Void) {
        guard let bookmarks, !bookmarkBusy else { return }
        bookmarkBusy = true
        reloadBookmarks()
        Task { [weak self] in
            do {
                try await operation(bookmarks)
                self?.feedback.stringValue = L10n.tr("settings.bookmarks.operation_succeeded")
            } catch {
                self?.feedback.stringValue = L10n.format("settings.bookmarks.operation_failed", error.localizedDescription)
            }
            self?.bookmarkBusy = false
            self?.reloadBookmarks()
        }
    }

    @objc private func detectProfiles() {
        runBookmarkOperation { try await $0.discoverProfiles(root: BookmarkStore.defaultChromeRoot) }
    }

    @objc private func refreshBookmarks() {
        runBookmarkOperation { try await $0.refreshSelected() }
    }

    @objc private func chooseChromeDirectory() {
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

    @objc private func clearBookmarks() {
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
                self?.feedback.stringValue = L10n.tr("settings.bookmarks.cleared")
            } catch { self?.feedback.stringValue = error.localizedDescription }
            self?.reloadBookmarks()
        }
    }

    @objc private func addDirectory() {
        guard let window else { return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.prompt = L10n.tr("common.add")
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let self else { return }
            self.paths = Array(Set(self.paths + panel.urls.map { $0.standardizedFileURL.path })).sorted()
            self.reloadDirectories()
        }
    }

    @objc private func removeDirectory() {
        guard paths.indices.contains(directories.indexOfSelectedItem) else { return }
        paths = paths.enumerated().filter { $0.offset != directories.indexOfSelectedItem }.map(\.element)
        reloadDirectories()
    }

    @objc private func clearHistory() {
        usage.clear()
        feedback.stringValue = L10n.tr("settings.usage_cleared")
    }

    @objc private func saveSettings() {
        let value = LauncherSettings(hotKey: hotKeyRecorder.binding ?? .optionSpace,
                                     searchDirectories: paths,
                                     searchEngine: SearchEngine.allCases[engine.indexOfSelectedItem],
                                     rememberUsage: remember.state == .on,
                                     webSearches: webSearchSettings.definitions,
                                     fallbackOnlyWhenNoResults: fallback.indexOfSelectedItem == 1,
                                     clipboardHotKey: clipboardHotKeyRecorder.binding ?? .optionCommandC,
                                     language: AppLanguage.allCases[languagePopup.indexOfSelectedItem])
        let languageChanged = value.language != store.settings.language
        do {
            try apply(value)
            feedback.stringValue = languageChanged ? L10n.tr("settings.restart_required") : L10n.tr("settings.saved")
        } catch {
            feedback.stringValue = error.localizedDescription
        }
    }
}
