import AppKit
import UniformTypeIdentifiers

/// Modal sheet for choosing an application (with live search or disk browse) and recording its shortcut.
@MainActor final class AppShortcutEditorSheet: NSObject {
    private struct AppOption: Equatable {
        let name: String
        let path: String
        let bundleIdentifier: String?
    }

    let sheetWindow: NSWindow
    private let searchField = NSSearchField()
    private let tableView = NSTableView()
    private let emptyLabel = NSTextField(wrappingLabelWithString: L10n.tr("app_shortcuts.sheet.no_results"))
    private let selectedSummaryLabel = NSTextField(labelWithString: "")
    private let browseButton: NSButton
    private let recorderView = HotKeyRecorderView(binding: nil, allowsClearing: true)
    private let errorBanner = SettingsStatusBanner()
    private let cancelButton: NSButton
    private let confirmButton: NSButton

    private let allOptions: [AppOption]
    private var filteredOptions: [AppOption] = []
    private var selectedOption: AppOption?
    private weak var parentWindow: NSWindow?
    private let onCommit: (AppShortcut) -> Result<Void, Error>
    private let onDismiss: () -> Void

    init(
        availableApps: [AppItem],
        existingPaths: Set<String>,
        onRecordingStateChanged: ((Bool) -> Void)?,
        onCommit: @escaping (AppShortcut) -> Result<Void, Error>,
        onDismiss: @escaping () -> Void
    ) {
        self.onCommit = onCommit
        self.onDismiss = onDismiss

        // Put unbound apps first, then already-bound apps, sorted alphabetically within each bucket.
        let sortedApps = availableApps.sorted { lhs, rhs in
            let lhsBound = existingPaths.contains(lhs.url.standardizedFileURL.path)
            let rhsBound = existingPaths.contains(rhs.url.standardizedFileURL.path)
            if lhsBound != rhsBound { return !lhsBound }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
        self.allOptions = sortedApps.map { item in
            AppOption(
                name: item.name,
                path: item.url.standardizedFileURL.path,
                bundleIdentifier: Bundle(url: item.url)?.bundleIdentifier
            )
        }
        self.filteredOptions = self.allOptions
        self.selectedOption = self.allOptions.first

        self.sheetWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 472, height: 446),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        self.browseButton = SettingsStyle.makeButton(
            title: L10n.tr("app_shortcuts.sheet.browse_other"),
            symbolName: "folder",
            primary: false,
            target: nil,
            action: nil
        )
        self.cancelButton = SettingsStyle.makeButton(
            title: L10n.tr("common.cancel"),
            primary: false,
            target: nil,
            action: nil
        )
        self.confirmButton = SettingsStyle.makeButton(
            title: L10n.tr("common.add"),
            primary: true,
            target: nil,
            action: nil
        )

        super.init()
        recorderView.onRecordingStateChanged = onRecordingStateChanged
        configureUI()
        selectFirstVisibleRow()
    }

    func present(on window: NSWindow) {
        parentWindow = window
        window.beginSheet(sheetWindow) { [weak self] _ in
            self?.sheetWindow.makeFirstResponder(nil)
            self?.onDismiss()
        }
        sheetWindow.makeFirstResponder(searchField)
    }

    private func configureUI() {
        sheetWindow.isReleasedWhenClosed = false
        let root = SettingsCanvasView(frame: NSRect(x: 0, y: 0, width: 472, height: 446))
        sheetWindow.contentView = root

        let titleLabel = NSTextField(labelWithString: L10n.tr("app_shortcuts.sheet.title"))
        titleLabel.font = .systemFont(ofSize: 16, weight: .semibold)
        titleLabel.textColor = .labelColor

        searchField.placeholderString = L10n.tr("app_shortcuts.sheet.search_placeholder")
        searchField.delegate = self
        searchField.setAccessibilityLabel(L10n.tr("app_shortcuts.sheet.search_placeholder"))
        searchField.translatesAutoresizingMaskIntoConstraints = false

        let listContainer = configureAppList()

        selectedSummaryLabel.font = SettingsStyle.rowSubtitleFont
        selectedSummaryLabel.textColor = SettingsStyle.secondaryText
        selectedSummaryLabel.lineBreakMode = .byTruncatingMiddle
        selectedSummaryLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        selectedSummaryLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        browseButton.target = self
        browseButton.action = #selector(browseAppClicked)
        browseButton.setContentHuggingPriority(.required, for: .horizontal)
        browseButton.setContentCompressionResistancePriority(.required, for: .horizontal)

        let footerSpacer = NSView()
        footerSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let pickerFooter = NSStackView(views: [selectedSummaryLabel, footerSpacer, browseButton])
        pickerFooter.orientation = .horizontal
        pickerFooter.alignment = .centerY
        pickerFooter.spacing = 10

        recorderView.setAccessibilityLabel(L10n.tr("app_shortcuts.recorder_accessibility"))
        recorderView.onChange = { [weak self] _ in
            self?.errorBanner.clear()
        }

        let hotkeyCard = SettingsCardView(rows: [
            SettingsRowView(
                title: L10n.tr("app_shortcuts.field.hotkey"),
                trailingViews: [recorderView],
                verticalPadding: 10
            ),
        ])
        hotkeyCard.setContentHuggingPriority(.required, for: .vertical)

        cancelButton.target = self
        cancelButton.action = #selector(cancelClicked)
        cancelButton.keyEquivalent = "\u{1b}"

        confirmButton.target = self
        confirmButton.action = #selector(confirmClicked)
        confirmButton.keyEquivalent = "\r"

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let actionsRow = NSStackView(views: [spacer, cancelButton, confirmButton])
        actionsRow.orientation = .horizontal
        actionsRow.alignment = .centerY
        actionsRow.spacing = 10

        let stack = NSStackView(views: [
            titleLabel,
            searchField,
            listContainer,
            pickerFooter,
            hotkeyCard,
            errorBanner,
            actionsRow,
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -20),
            stack.topAnchor.constraint(equalTo: root.topAnchor, constant: 20),
            stack.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -18),
            searchField.widthAnchor.constraint(equalTo: stack.widthAnchor),
            listContainer.widthAnchor.constraint(equalTo: stack.widthAnchor),
            listContainer.heightAnchor.constraint(equalToConstant: 208),
            pickerFooter.widthAnchor.constraint(equalTo: stack.widthAnchor),
            hotkeyCard.widthAnchor.constraint(equalTo: stack.widthAnchor),
            errorBanner.widthAnchor.constraint(equalTo: stack.widthAnchor),
            actionsRow.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])

        updateSelectedSummary()
    }

    private func configureAppList() -> NSView {
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("appOption"))
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.rowHeight = 42
        tableView.intercellSpacing = NSSize(width: 0, height: 2)
        tableView.style = .inset
        tableView.backgroundColor = .clear
        tableView.allowsMultipleSelection = false
        tableView.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        tableView.sizeLastColumnToFit()
        tableView.dataSource = self
        tableView.delegate = self
        tableView.setAccessibilityLabel(L10n.tr("app_shortcuts.field.app"))

        let scroll = NSScrollView()
        scroll.documentView = tableView
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.translatesAutoresizingMaskIntoConstraints = false

        emptyLabel.font = SettingsStyle.rowSubtitleFont
        emptyLabel.textColor = .secondaryLabelColor
        emptyLabel.alignment = .center
        emptyLabel.isHidden = !filteredOptions.isEmpty
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false

        let container = SettingsCardView()
        container.addSubview(scroll)
        container.addSubview(emptyLabel)
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 4),
            scroll.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -4),
            scroll.topAnchor.constraint(equalTo: container.topAnchor, constant: 4),
            scroll.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -4),
            emptyLabel.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            emptyLabel.leadingAnchor.constraint(greaterThanOrEqualTo: container.leadingAnchor, constant: 20),
            emptyLabel.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -20),
        ])
        return container
    }

    private func selectFirstVisibleRow() {
        emptyLabel.isHidden = !filteredOptions.isEmpty
        if let selected = selectedOption,
           let idx = filteredOptions.firstIndex(where: { $0.path == selected.path }) {
            tableView.selectRowIndexes(IndexSet(integer: idx), byExtendingSelection: false)
            tableView.scrollRowToVisible(idx)
        } else if !filteredOptions.isEmpty {
            selectedOption = filteredOptions[0]
            tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
            tableView.scrollRowToVisible(0)
        } else {
            tableView.deselectAll(nil)
        }
        updateSelectedSummary()
    }

    private func updateSelectedSummary() {
        if let selected = selectedOption {
            selectedSummaryLabel.stringValue = "\(L10n.tr("app_shortcuts.sheet.selected_app"))：\(selected.name)"
            selectedSummaryLabel.toolTip = selected.path
        } else {
            selectedSummaryLabel.stringValue = L10n.tr("app_shortcuts.choose_prompt")
            selectedSummaryLabel.toolTip = nil
        }
    }

    @objc private func browseAppClicked() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.applicationBundle]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = L10n.tr("common.add")
        panel.beginSheetModal(for: sheetWindow) { [weak self] response in
            guard response == .OK, let self, let url = panel.url?.standardizedFileURL else { return }
            let rawName = url.deletingPathExtension().lastPathComponent
            let display = FileManager.default.displayName(atPath: url.path)
            let cleanName = display.hasSuffix(".app") ? String(display.dropLast(4)) : display
            let chosen = AppOption(
                name: cleanName.isEmpty ? rawName : cleanName,
                path: url.path,
                bundleIdentifier: Bundle(url: url)?.bundleIdentifier
            )
            self.selectedOption = chosen
            if let existingIndex = self.filteredOptions.firstIndex(where: { $0.path == chosen.path }) {
                self.tableView.selectRowIndexes(IndexSet(integer: existingIndex), byExtendingSelection: false)
                self.tableView.scrollRowToVisible(existingIndex)
            } else {
                self.tableView.deselectAll(nil)
            }
            self.errorBanner.clear()
            self.updateSelectedSummary()
        }
    }

    @objc private func cancelClicked() {
        sheetWindow.makeFirstResponder(nil)
        parentWindow?.endSheet(sheetWindow, returnCode: .cancel)
        sheetWindow.orderOut(nil)
    }

    @objc private func confirmClicked() {
        sheetWindow.makeFirstResponder(nil)
        guard let option = selectedOption, !option.path.isEmpty, !option.name.isEmpty else {
            errorBanner.show(AppShortcutValidationError.invalidApplication.localizedDescription, level: .error)
            return
        }
        guard let hotKey = recorderView.binding else {
            errorBanner.show(AppShortcutValidationError.missingHotKey.localizedDescription, level: .error)
            return
        }
        let created = AppShortcut(
            id: "app.\(UUID().uuidString)",
            bundleIdentifier: option.bundleIdentifier,
            appPath: option.path,
            appName: option.name,
            hotKey: hotKey,
            isEnabled: true
        )
        switch onCommit(created) {
        case .success:
            parentWindow?.endSheet(sheetWindow, returnCode: .OK)
            sheetWindow.orderOut(nil)
        case .failure(let error):
            errorBanner.show(error.localizedDescription, level: .error)
        }
    }
}

extension AppShortcutEditorSheet: NSSearchFieldDelegate {
    func controlTextDidChange(_ obj: Notification) {
        let query = searchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if query.isEmpty {
            filteredOptions = allOptions
        } else {
            filteredOptions = allOptions.filter {
                $0.name.lowercased().contains(query) || $0.path.lowercased().contains(query)
            }
        }
        tableView.reloadData()
        selectFirstVisibleRow()
    }
}

extension AppShortcutEditorSheet: NSTableViewDataSource, NSTableViewDelegate {
    func numberOfRows(in tableView: NSTableView) -> Int {
        filteredOptions.count
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        let row = tableView.selectedRow
        guard filteredOptions.indices.contains(row) else { return }
        selectedOption = filteredOptions[row]
        errorBanner.clear()
        updateSelectedSummary()
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard filteredOptions.indices.contains(row) else { return nil }
        let option = filteredOptions[row]
        let cell = NSTableCellView()

        let icon = NSImageView(image: SettingsStyle.applicationIcon(forPath: option.path))
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.translatesAutoresizingMaskIntoConstraints = false

        let nameLabel = NSTextField(labelWithString: option.name)
        nameLabel.font = SettingsStyle.rowTitleFont
        nameLabel.textColor = .labelColor
        nameLabel.lineBreakMode = .byTruncatingTail

        let pathLabel = NSTextField(labelWithString: SettingsStyle.abbreviatedPath(option.path))
        pathLabel.font = .systemFont(ofSize: 10.5)
        pathLabel.textColor = SettingsStyle.secondaryText
        pathLabel.lineBreakMode = .byTruncatingMiddle

        let textStack = NSStackView(views: [nameLabel, pathLabel])
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 1
        textStack.translatesAutoresizingMaskIntoConstraints = false

        cell.addSubview(icon)
        cell.addSubview(textStack)
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 10),
            icon.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 24),
            icon.heightAnchor.constraint(equalToConstant: 24),
            textStack.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 10),
            textStack.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -10),
            textStack.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])
        return cell
    }
}
