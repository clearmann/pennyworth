import AppKit
import Carbon

/// AppKit presentation; search and execution state live in LauncherModel.
@MainActor final class LauncherViewController: NSViewController {
    static let panelSize = NSSize(width: 680, height: 420)
    private let model: LauncherModel
    private let searchField = NSTextField()
    private lazy var headerView = SearchHeaderView(symbolName: "magnifyingglass", searchField: searchField)
    private let tableView = LauncherResultsTableView()
    private let status = NSTextField(labelWithString: "")
    private lazy var footerView = StatusFooterView(statusLabel: status)
    private let scrollView = NSScrollView()
    private let iconCache = NSCache<NSURL, NSImage>()
    private var rendering = false
    var onDismiss: (() -> Void)?
    var onSettings: (() -> Void)?
    var onHeightChanged: ((CGFloat) -> Void)?

    init(model: LauncherModel) {
        self.model = model
        super.init(nibName: nil, bundle: nil)
        model.onChange = { [weak self] in self?.render() }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func loadView() {
        let effect = FloatingPanelRootView(frame: NSRect(origin: .zero, size: Self.panelSize))
        view = effect
        configureSearch()
        configureTable()
        status.setAccessibilityIdentifier("launcher.status")
        headerView.badge.onTap = { [weak self] in self?.onSettings?() }
        [headerView, scrollView, footerView].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            effect.addSubview($0)
        }
        NSLayoutConstraint.activate([
            headerView.topAnchor.constraint(equalTo: effect.topAnchor),
            headerView.leadingAnchor.constraint(equalTo: effect.leadingAnchor),
            headerView.trailingAnchor.constraint(equalTo: effect.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: headerView.bottomAnchor, constant: 6),
            scrollView.leadingAnchor.constraint(equalTo: effect.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: effect.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: footerView.topAnchor, constant: -6),
            footerView.leadingAnchor.constraint(equalTo: effect.leadingAnchor),
            footerView.trailingAnchor.constraint(equalTo: effect.trailingAnchor),
            footerView.bottomAnchor.constraint(equalTo: effect.bottomAnchor),
        ])
        render()
    }

    private func configureSearch() {
        searchField.placeholderString = L10n.tr("launcher.search_placeholder")
        searchField.delegate = self
        searchField.setAccessibilityLabel(L10n.tr("launcher.search_accessibility"))
        searchField.setAccessibilityIdentifier("launcher.query")
    }

    private func configureTable() {
        FloatingPanelChrome.configureResultsTable(
            tableView,
            in: scrollView,
            columnIdentifier: "result",
            width: Self.panelSize.width,
            accessibilityLabel: L10n.tr("launcher.results_accessibility")
        )
        tableView.dataSource = self
        tableView.delegate = self
        tableView.target = self
        tableView.doubleAction = #selector(execute)
    }

    func focusSearchField(reset: Bool = true) {
        _ = view
        if reset { searchField.stringValue = ""; model.beginSession() }
        view.window?.makeFirstResponder(searchField)
    }

    private func render() {
        guard isViewLoaded else { return }
        rendering = true
        defer { rendering = false }
        searchField.isEditable = !model.isExecuting
        status.stringValue = model.isExecuting ? L10n.tr("launcher.executing") : model.snapshot.message
        updateHeaderBadge()
        tableView.reloadData()
        scrollView.isHidden = model.snapshot.results.isEmpty
        if let index = model.snapshot.results.firstIndex(where: { $0.id == model.selectedID }) {
            tableView.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
            tableView.scrollRowToVisible(index)
        } else { tableView.deselectAll(nil) }
        onHeightChanged?(PennyworthTheme.collapsedPanelHeight + CGFloat(min(model.snapshot.results.count, 7)) * PennyworthTheme.rowHeight)
    }

    @objc private func execute() { model.executeSelected() }

    private func updateHeaderBadge() {
        guard !model.query.isEmpty,
              let active = model.snapshot.results.first(where: { $0.id == model.selectedID }) ?? model.snapshot.results.first else {
            headerView.badge.update(text: "⌘,", style: .neutral, accessibilityLabel: L10n.tr("menu.settings"))
            return
        }
        let badgeText: String
        switch active.action {
        case .copyText: badgeText = L10n.tr("launcher.badge.calculator")
        case .openFile, .revealFile: badgeText = L10n.tr("launcher.badge.files")
        case .openURL:
            badgeText = active.id.hasPrefix("bookmark:")
                ? L10n.tr("launcher.badge.bookmarks")
                : L10n.tr("launcher.badge.web")
        case .startScreenshot, .pinClipboardImage: badgeText = L10n.tr("launcher.badge.screenshot")
        case .openApplication:
            headerView.badge.update(text: "⌘,", style: .neutral, accessibilityLabel: L10n.tr("menu.settings"))
            return
        }
        headerView.badge.update(text: badgeText, style: .accent)
    }
}

extension LauncherViewController: NSTextFieldDelegate {
    func controlTextDidChange(_ notification: Notification) {
        if let editor = searchField.currentEditor() as? NSTextView, editor.hasMarkedText() { return }
        model.updateQuery(searchField.stringValue)
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        guard !textView.hasMarkedText() else { return false }
        switch selector {
        case #selector(NSResponder.moveDown(_:)): model.moveSelection(by: 1)
        case #selector(NSResponder.moveUp(_:)): model.moveSelection(by: -1)
        case #selector(NSResponder.insertNewline(_:)): execute()
        case #selector(NSResponder.cancelOperation(_:)): onDismiss?()
        default: return false
        }
        return true
    }
}

extension LauncherViewController: NSTableViewDataSource, NSTableViewDelegate {
    func numberOfRows(in tableView: NSTableView) -> Int { model.snapshot.results.count }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard !rendering, model.snapshot.results.indices.contains(tableView.selectedRow) else { return }
        model.select(model.snapshot.results[tableView.selectedRow].id)
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let result = model.snapshot.results[row]
        let identifier = NSUserInterfaceItemIdentifier("ResultCell")
        let cell = (tableView.makeView(withIdentifier: identifier, owner: nil) as? ResultCellView)
            ?? ResultCellView(identifier: identifier)
        var icon = NSImage(systemSymbolName: result.symbol, accessibilityDescription: nil)
        if let url = result.fileURL {
            icon = iconCache.object(forKey: url as NSURL) ?? NSWorkspace.shared.icon(forFile: url.path)
            if let icon { iconCache.setObject(icon, forKey: url as NSURL) }
        }
        cell.configure(
            result,
            icon: icon,
            selected: result.id == model.selectedID,
            usesSymbolBackground: result.fileURL == nil
        )
        return cell
    }
}

private final class LauncherResultsTableView: NSTableView {
    override func keyDown(with event: NSEvent) {
        guard event.keyCode == UInt16(kVK_Return) || event.keyCode == UInt16(kVK_ANSI_KeypadEnter) else {
            super.keyDown(with: event)
            return
        }
        if let doubleAction { sendAction(doubleAction, to: target) }
    }
}
