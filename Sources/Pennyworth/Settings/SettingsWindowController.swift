import AppKit

private final class SettingsPageHost: NSView {
    override var isFlipped: Bool { true }
}

@MainActor final class SettingsWindowController: NSWindowController {
    static let pageTitles = ["通用", "默认结果", "文件搜索", "网页搜索", "网页书签", "计算器"]
    private let store: SettingsStore
    private let usage: UsageStore
    private let bookmarks: BookmarkStore?
    private let apply: (LauncherSettings) throws -> Void
    private let hotKeyRecorder = HotKeyRecorderView(binding: .optionSpace)
    private let clipboardHotKeyRecorder = HotKeyRecorderView(binding: .optionCommandC)
    private let engine = NSPopUpButton()
    private let fallback = NSPopUpButton()
    private let remember = NSButton(checkboxWithTitle: "记住应用使用频率", target: nil, action: nil)
    private let directories = NSPopUpButton()
    private let feedback = NSTextField(wrappingLabelWithString: "")
    private let pageHost = SettingsPageHost()
    private var pages: [String: NSStackView] = [:]
    private var navigation: [NSButton] = []
    private var pageBottom: NSLayoutConstraint?
    private var paths: [String] = []
    private(set) var selectedPageTitle = "通用"
    private let bookmarkEnabled = NSButton(checkboxWithTitle: "搜索 Chrome 书签", target: nil, action: nil)
    private let defaultBookmarks = NSButton(checkboxWithTitle: "网页书签", target: nil, action: nil)
    private let bookmarkInDefault = NSButton(checkboxWithTitle: "在默认搜索结果中显示书签", target: nil, action: nil)
    private let matchTitle = NSButton(checkboxWithTitle: "标题", target: nil, action: nil)
    private let matchURL = NSButton(checkboxWithTitle: "网址", target: nil, action: nil)
    private let matchFolders = NSButton(checkboxWithTitle: "文件夹名称", target: nil, action: nil)
    private let profileList = NSStackView()
    private let bookmarkStatus = NSTextField(wrappingLabelWithString: "尚未导入书签。")
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
        window.title = "Pennyworth 设置"
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
        fallback.selectItem(at: value.fallbackOnlyWhenNoResults ? 1 : 0)
        remember.state = value.rememberUsage ? .on : .off
        paths = value.searchDirectories
        reloadDirectories()
        feedback.stringValue = store.warning ?? "常规设置点击保存生效；书签选项与导入操作立即保存。"
        super.showWindow(sender)
        reloadBookmarks()
    }

    private func configure() {
        guard let content = window?.contentView else { return }
        hotKeyRecorder.setAccessibilityLabel("全局热键")
        clipboardHotKeyRecorder.setAccessibilityLabel("剪贴板历史热键")
        engine.addItems(withTitles: SearchEngine.allCases.map(\.title))
        fallback.addItems(withTitles: ["始终显示在最后", "仅无本地匹配时显示"])
        engine.setAccessibilityLabel("默认搜索引擎")
        fallback.setAccessibilityLabel("网页搜索兜底")
        directories.setAccessibilityLabel("文件搜索目录")
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
            button.setAccessibilityLabel("设置页面：\(title)")
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
        let save = NSButton(title: "保存", target: self, action: #selector(saveSettings))
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
        selectPage("通用")
    }

    private func buildPages() {
        addPage("通用", description: "设置唤出方式与应用使用记录。", controls: [
            row("全局热键", hotKeyRecorder),
            row("剪贴板历史热键", clipboardHotKeyRecorder),
            remember,
            NSButton(title: "清除使用记录", target: self, action: #selector(clearHistory)),
        ])
        defaultBookmarks.target = self
        defaultBookmarks.action = #selector(bookmarkPreferenceChanged(_:))
        defaultBookmarks.setAccessibilityLabel("默认结果中的网页书签")
        bookmarkInDefault.setAccessibilityLabel("默认结果中的网页书签选项")
        let bookmarkLink = NSButton(title: "设置书签…", target: self, action: #selector(openBookmarks))
        addPage("默认结果", description: "选择直接输入关键词时显示的内容。", controls: [
            note("应用始终包含在默认结果中。"),
            NSStackView(views: [defaultBookmarks, bookmarkLink]),
            note("文件通过空格、open 或 find 搜索。关闭默认书签展示后，仍可使用 bm 搜索。"),
            row("网页搜索兜底", fallback),
        ])
        addPage("文件搜索", description: "选择文件名搜索覆盖的目录。", controls: [
            row("文件搜索目录", directories),
            NSStackView(views: [NSButton(title: "添加目录…", target: self, action: #selector(addDirectory)),
                               NSButton(title: "移除所选", target: self, action: #selector(removeDirectory))]),
            note("文件搜索仅覆盖所选目录的 Spotlight 索引。建议添加文稿、桌面或下载。"),
            note("使用 open 打开文件，使用 find 在 Finder 中显示文件。"),
        ])
        addPage("网页搜索", description: "在浏览器中执行搜索，输入时不会发送网络请求。", controls: [
            row("默认搜索引擎", engine), note("也可使用 google、bing 或 ddg 关键词指定搜索引擎。"),
        ])
        for button in [bookmarkEnabled, bookmarkInDefault, matchTitle, matchURL, matchFolders] {
            button.target = self
            button.action = #selector(bookmarkPreferenceChanged(_:))
        }
        defaultBookmarks.setAccessibilityLabel("默认结果中的网页书签")
        bookmarkInDefault.setAccessibilityLabel("默认结果中的网页书签")
        profileList.orientation = .vertical
        profileList.alignment = .leading
        profileList.spacing = 8
        let detect = NSButton(title: "检测个人资料", target: self, action: #selector(detectProfiles))
        let choose = NSButton(title: "选择 Chrome 数据目录…", target: self, action: #selector(chooseChromeDirectory))
        let refresh = NSButton(title: "立即导入 / 刷新", target: self, action: #selector(refreshBookmarks))
        let clear = NSButton(title: "清除已导入书签…", target: self, action: #selector(clearBookmarks))
        bookmarkButtons = [detect, choose, refresh, clear]
        bookmarkStatus.font = .systemFont(ofSize: 12)
        bookmarkStatus.textColor = .secondaryLabelColor
        addPage("网页书签", description: "从 Chrome 导入书签。数据仅保存在本机，不修改浏览器中的原始书签。", controls: [
            bookmarkEnabled, row("Chrome 个人资料", profileList),
            NSStackView(views: [detect, choose]), refresh, bookmarkStatus,
            bookmarkInDefault, row("专用关键词", NSTextField(labelWithString: "bm")),
            row("匹配范围", NSStackView(views: [matchTitle, matchURL, matchFolders])),
            row("打开方式", NSTextField(labelWithString: "使用系统默认浏览器")),
            clear, note("书签选项立即保存。清除只删除 Pennyworth 的副本，不影响 Chrome。"),
        ])
        addPage("计算器", description: "直接输入表达式，按回车复制计算结果。", controls: [
            note("支持四则运算、小数、括号和一元正负号。"),
            note("例如：23 * 17、(12 + 8) / 4。使用 = 前缀可明确进入计算模式。"),
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
        if title == "网页书签" {
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
    @objc private func openBookmarks() { selectPage("网页书签") }

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
        directories.addItems(withTitles: paths.isEmpty ? ["未配置（不搜索文件）"] : paths)
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
            profileList.addArrangedSubview(note("书签服务不可用。"))
            return
        }
        if bookmarks.profiles.isEmpty { profileList.addArrangedSubview(note("尚未检测。请选择要导入的 Chrome 个人资料。")) }
        for profile in bookmarks.profiles {
            let count = bookmarks.snapshots[profile.id]?.entries.count
            let button = NSButton(checkboxWithTitle: "\(profile.name) · \(count.map { "\($0) 条 · 已导入" } ?? "未导入")",
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
            bookmarkStatus.stringValue = "正在读取 Chrome 书签…"
        } else if let date = snapshots.map(\.importedAt).max() {
            bookmarkStatus.stringValue = "上次成功导入：\(date.formatted(date: .abbreviated, time: .shortened))\n已导入 \(snapshots.reduce(0) { $0 + $1.entries.count }) 条，跳过 \(snapshots.reduce(0) { $0 + $1.skippedCount }) 条不支持的网址。"
        } else {
            bookmarkStatus.stringValue = "尚未导入书签。勾选个人资料后，点击立即导入 / 刷新。"
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
            feedback.stringValue = "书签选项已保存。常规设置仍需点击保存。"
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
                self?.feedback.stringValue = "书签操作完成，数据已保存。"
            } catch {
                self?.feedback.stringValue = "书签操作失败：\(error.localizedDescription)。保留上次成功导入的数据。"
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
        panel.message = "请选择包含 Default 或 Profile 子目录的 Chrome 数据目录。"
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.runBookmarkOperation { try await $0.discoverProfiles(root: url) }
        }
    }

    @objc private func clearBookmarks() {
        guard let window, let bookmarks else { return }
        let alert = NSAlert()
        alert.messageText = "清除已导入书签？"
        alert.informativeText = "只删除 Pennyworth 保存的书签副本，不会修改 Chrome。之后可以重新导入。"
        alert.addButton(withTitle: "取消")
        alert.addButton(withTitle: "清除")
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertSecondButtonReturn else { return }
            do {
                try bookmarks.clearImportedData()
                self?.feedback.stringValue = "已清除 Pennyworth 中的书签副本。"
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
        panel.prompt = "添加"
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
        feedback.stringValue = "使用记录已清除。"
    }

    @objc private func saveSettings() {
        let value = LauncherSettings(hotKey: hotKeyRecorder.binding ?? .optionSpace,
                                     searchDirectories: paths,
                                     searchEngine: SearchEngine.allCases[engine.indexOfSelectedItem],
                                     rememberUsage: remember.state == .on,
                                     fallbackOnlyWhenNoResults: fallback.indexOfSelectedItem == 1,
                                     clipboardHotKey: clipboardHotKeyRecorder.binding ?? .optionCommandC)
        do {
            try apply(value)
            feedback.stringValue = "设置已保存。"
        } catch {
            feedback.stringValue = error.localizedDescription
        }
    }
}
