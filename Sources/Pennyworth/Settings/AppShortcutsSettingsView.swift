import AppKit
import UniformTypeIdentifiers

@MainActor final class AppShortcutsSettingsView: NSView {
    struct Draft: Equatable {
        let id: String
        let bundleIdentifier: String?
        let appPath: String
        let appName: String
        let hotKey: HotKeyPreset?
        let isEnabled: Bool
    }

    private struct AppOption: Equatable {
        let name: String
        let path: String
        let bundleIdentifier: String?
    }

    private let tableView = NSTableView()
    private let appPopup = NSPopUpButton()
    private let chooseAppButton = NSButton(title: L10n.tr("app_shortcuts.choose_app"), target: nil, action: nil)
    private let recorderView = HotKeyRecorderView(binding: nil)
    private let addButton = NSButton(title: L10n.tr("app_shortcuts.add"), target: nil, action: nil)
    private let removeButton = NSButton(title: L10n.tr("app_shortcuts.remove"), target: nil, action: nil)
    private let enabledButton = NSButton(checkboxWithTitle: L10n.tr("common.enabled"), target: nil, action: nil)
    private var availableApps: [AppItem] = []
    private var appOptions: [AppOption] = []
    private(set) var drafts: [Draft] = []

    var onRecordingStateChanged: ((Bool) -> Void)? {
        didSet { recorderView.onRecordingStateChanged = onRecordingStateChanged }
    }

    init() {
        super.init(frame: .zero)
        configure()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func reload(_ shortcuts: [AppShortcut], availableApps: [AppItem]) {
        self.availableApps = availableApps
        drafts = shortcuts.map {
            Draft(
                id: $0.id,
                bundleIdentifier: $0.bundleIdentifier,
                appPath: $0.appPath,
                appName: $0.appName,
                hotKey: $0.hotKey,
                isEnabled: $0.isEnabled
            )
        }
        tableView.reloadData()
        selectRow(at: drafts.isEmpty ? -1 : 0)
    }

    func updateAvailableApps(_ apps: [AppItem]) {
        availableApps = apps
        updateEditor()
    }

    func validatedShortcuts() throws -> [AppShortcut] {
        try drafts.map { draft in
            guard !draft.appPath.isEmpty,
                  !draft.appName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw AppShortcutValidationError.invalidApplication
            }
            guard let hotKey = draft.hotKey else {
                throw AppShortcutValidationError.missingHotKey
            }
            return AppShortcut(
                id: draft.id,
                bundleIdentifier: draft.bundleIdentifier,
                appPath: draft.appPath,
                appName: draft.appName,
                hotKey: hotKey,
                isEnabled: draft.isEnabled
            )
        }
    }

    private func configure() {
        translatesAutoresizingMaskIntoConstraints = false
        configureTable()
        configureControls()
        let scroll = tableView.enclosingScrollView!
        let editor = buildEditorStack()
        let actions = NSStackView(views: [addButton, removeButton, enabledButton])
        actions.spacing = 12
        actions.translatesAutoresizingMaskIntoConstraints = false
        addSubview(editor)
        addSubview(actions)
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: trailingAnchor),
            scroll.topAnchor.constraint(equalTo: topAnchor),
            scroll.heightAnchor.constraint(equalToConstant: 184),
            editor.leadingAnchor.constraint(equalTo: leadingAnchor),
            editor.topAnchor.constraint(equalTo: scroll.bottomAnchor, constant: 14),
            actions.leadingAnchor.constraint(equalTo: leadingAnchor),
            actions.topAnchor.constraint(equalTo: editor.bottomAnchor, constant: 14),
            actions.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    private func configureTable() {
        for (id, key, width) in [
            ("app", "app_shortcuts.column.app", 150.0),
            ("hotkey", "app_shortcuts.column.hotkey", 110.0),
            ("path", "app_shortcuts.column.path", 220.0),
            ("enabled", "common.enabled", 50.0),
        ] {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id))
            column.title = L10n.tr(key)
            column.width = width
            tableView.addTableColumn(column)
        }
        tableView.dataSource = self
        tableView.delegate = self
        tableView.rowHeight = 24
        tableView.intercellSpacing = NSSize(width: 4, height: 2)
        tableView.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        tableView.allowsMultipleSelection = false
        tableView.setAccessibilityLabel(L10n.tr("app_shortcuts.list_accessibility"))
        let scroll = NSScrollView()
        scroll.documentView = tableView
        scroll.hasVerticalScroller = true
        scroll.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scroll)
    }

    private func configureControls() {
        appPopup.target = self
        appPopup.action = #selector(appSelectionChanged)
        appPopup.widthAnchor.constraint(equalToConstant: 240).isActive = true
        appPopup.setAccessibilityLabel(L10n.tr("app_shortcuts.field.app"))
        chooseAppButton.target = self
        chooseAppButton.action = #selector(chooseApplicationFromDisk)
        recorderView.setAccessibilityLabel(L10n.tr("app_shortcuts.recorder_accessibility"))
        recorderView.onChange = { [weak self] binding in
            self?.updateSelectedHotKey(binding)
        }
        addButton.target = self
        addButton.action = #selector(addShortcut)
        removeButton.target = self
        removeButton.action = #selector(removeShortcut)
        enabledButton.target = self
        enabledButton.action = #selector(toggleEnabled)
        enabledButton.setAccessibilityLabel(L10n.tr("app_shortcuts.enable_selected"))
    }

    private func buildEditorStack() -> NSStackView {
        let appPickerRow = NSStackView(views: [appPopup, chooseAppButton])
        appPickerRow.spacing = 8
        let stack = NSStackView(views: [
            labeledRow(L10n.tr("app_shortcuts.field.app"), appPickerRow),
            labeledRow(L10n.tr("app_shortcuts.field.hotkey"), recorderView),
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }

    private func labeledRow(_ title: String, _ control: NSView) -> NSView {
        let label = NSTextField(labelWithString: title)
        label.widthAnchor.constraint(equalToConstant: 92).isActive = true
        let row = NSStackView(views: [label, control])
        row.alignment = .centerY
        row.spacing = 12
        return row
    }

    private func selectRow(at index: Int) {
        if drafts.indices.contains(index) {
            tableView.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
            tableView.scrollRowToVisible(index)
        } else {
            tableView.deselectAll(nil)
        }
        updateEditor()
    }

    private func updateEditor() {
        let index = tableView.selectedRow
        guard drafts.indices.contains(index) else {
            appOptions = []
            appPopup.removeAllItems()
            appPopup.addItem(withTitle: L10n.tr("app_shortcuts.no_selection"))
            appPopup.isEnabled = false
            chooseAppButton.isEnabled = false
            recorderView.setBinding(nil)
            recorderView.isEnabled = false
            removeButton.isEnabled = false
            enabledButton.isEnabled = false
            enabledButton.state = .off
            return
        }
        let current = drafts[index]
        rebuildAppPopup(selected: current)
        appPopup.isEnabled = !appOptions.isEmpty
        chooseAppButton.isEnabled = true
        recorderView.isEnabled = true
        recorderView.setBinding(current.hotKey)
        removeButton.isEnabled = true
        enabledButton.isEnabled = true
        enabledButton.state = current.isEnabled ? .on : .off
    }

    private func rebuildAppPopup(selected: Draft) {
        var options = availableApps.map { item in
            AppOption(
                name: item.name,
                path: item.url.standardizedFileURL.path,
                bundleIdentifier: Bundle(url: item.url)?.bundleIdentifier
            )
        }
        if !selected.appPath.isEmpty, !options.contains(where: { $0.path == selected.appPath }) {
            options = [AppOption(name: selected.appName, path: selected.appPath, bundleIdentifier: selected.bundleIdentifier)] + options
        }
        appOptions = options
        appPopup.removeAllItems()
        if options.isEmpty {
            appPopup.addItem(withTitle: L10n.tr("app_shortcuts.choose_prompt"))
            return
        }
        for (idx, option) in options.enumerated() {
            let duplicateName = options.filter { $0.name == option.name }.count > 1
            let title = duplicateName ? "\(option.name) (\(option.path))" : option.name
            appPopup.menu?.addItem(withTitle: title, action: nil, keyEquivalent: "")
            if option.path == selected.appPath {
                appPopup.selectItem(at: idx)
            }
        }
    }

    private func replaceSelected(with updated: Draft) {
        let index = tableView.selectedRow
        guard drafts.indices.contains(index) else { return }
        drafts = drafts.enumerated().map { $0.offset == index ? updated : $0.element }
        tableView.reloadData(
            forRowIndexes: IndexSet(integer: index),
            columnIndexes: IndexSet(integersIn: 0..<tableView.numberOfColumns)
        )
    }

    private func updateSelectedHotKey(_ binding: HotKeyPreset?) {
        let index = tableView.selectedRow
        guard drafts.indices.contains(index) else { return }
        let current = drafts[index]
        replaceSelected(with: Draft(
            id: current.id,
            bundleIdentifier: current.bundleIdentifier,
            appPath: current.appPath,
            appName: current.appName,
            hotKey: binding,
            isEnabled: current.isEnabled
        ))
    }

    @objc private func appSelectionChanged() {
        let index = tableView.selectedRow
        let optionIndex = appPopup.indexOfSelectedItem
        guard drafts.indices.contains(index), appOptions.indices.contains(optionIndex) else { return }
        let current = drafts[index]
        let option = appOptions[optionIndex]
        replaceSelected(with: Draft(
            id: current.id,
            bundleIdentifier: option.bundleIdentifier,
            appPath: option.path,
            appName: option.name,
            hotKey: current.hotKey,
            isEnabled: current.isEnabled
        ))
    }

    @objc private func chooseApplicationFromDisk() {
        guard let window else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.applicationBundle]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = L10n.tr("common.add")
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let self, let url = panel.url?.standardizedFileURL else { return }
            self.applyChosenApplicationURL(url)
        }
    }

    private func applyChosenApplicationURL(_ url: URL) {
        let index = tableView.selectedRow
        guard drafts.indices.contains(index) else { return }
        let rawName = url.deletingPathExtension().lastPathComponent
        let display = FileManager.default.displayName(atPath: url.path)
        let cleanName = display.hasSuffix(".app") ? String(display.dropLast(4)) : display
        let current = drafts[index]
        let updated = Draft(
            id: current.id,
            bundleIdentifier: Bundle(url: url)?.bundleIdentifier,
            appPath: url.path,
            appName: cleanName.isEmpty ? rawName : cleanName,
            hotKey: current.hotKey,
            isEnabled: current.isEnabled
        )
        replaceSelected(with: updated)
        updateEditor()
    }

    @objc private func addShortcut() {
        let existingPaths = Set(drafts.map(\.appPath))
        let defaultApp = availableApps.first { !existingPaths.contains($0.url.standardizedFileURL.path) }
            ?? availableApps.first
        let path = defaultApp?.url.standardizedFileURL.path ?? ""
        let bundleID = defaultApp.flatMap { Bundle(url: $0.url)?.bundleIdentifier }
        let created = Draft(
            id: "app.\(UUID().uuidString)",
            bundleIdentifier: bundleID,
            appPath: path,
            appName: defaultApp?.name ?? "",
            hotKey: nil,
            isEnabled: true
        )
        drafts = drafts + [created]
        tableView.reloadData()
        selectRow(at: drafts.count - 1)
    }

    @objc private func removeShortcut() {
        let index = tableView.selectedRow
        guard drafts.indices.contains(index) else { return }
        drafts = drafts.enumerated().filter { $0.offset != index }.map(\.element)
        tableView.reloadData()
        selectRow(at: min(index, drafts.count - 1))
    }

    @objc private func toggleEnabled() {
        let index = tableView.selectedRow
        guard drafts.indices.contains(index) else { return }
        let current = drafts[index]
        replaceSelected(with: Draft(
            id: current.id,
            bundleIdentifier: current.bundleIdentifier,
            appPath: current.appPath,
            appName: current.appName,
            hotKey: current.hotKey,
            isEnabled: enabledButton.state == .on
        ))
    }
}

extension AppShortcutsSettingsView: NSTableViewDataSource, NSTableViewDelegate {
    func numberOfRows(in tableView: NSTableView) -> Int { drafts.count }

    func tableViewSelectionDidChange(_ notification: Notification) { updateEditor() }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard drafts.indices.contains(row), let id = tableColumn?.identifier.rawValue else { return nil }
        let draft = drafts[row]
        let text: String
        switch id {
        case "app":
            text = draft.appName.isEmpty ? L10n.tr("app_shortcuts.choose_prompt") : draft.appName
        case "hotkey":
            text = draft.hotKey?.title ?? L10n.tr("hotkey.not_set")
        case "path":
            text = draft.appPath
        case "enabled":
            text = L10n.tr(draft.isEnabled ? "common.yes" : "common.no")
        default:
            return nil
        }
        let cell = NSTextField(labelWithString: text)
        cell.lineBreakMode = .byTruncatingMiddle
        return cell
    }
}
