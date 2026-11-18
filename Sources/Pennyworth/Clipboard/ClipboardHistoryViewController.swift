import AppKit

@MainActor final class ClipboardHistoryViewController: NSViewController {
    static let panelSize = NSSize(width: 680, height: 420)
    private static let imagePreviewPanelHeight: CGFloat = 360

    private let model: ClipboardHistoryModel
    private let onRestore: (ClipboardItem) -> Void
    private let searchField = NSTextField()
    private lazy var headerView = SearchHeaderView(symbolName: "doc.on.clipboard", searchField: searchField)
    private let tableView = NSTableView()
    private let status = NSTextField(labelWithString: "")
    private lazy var footerView = StatusFooterView(statusLabel: status)
    private let scrollView = NSScrollView()
    private let contentStack = NSStackView()
    private let imagePreview = ClipboardImagePreviewView()
    private var rendering = false

    var onDismiss: (() -> Void)?
    var onHeightChanged: ((CGFloat) -> Void)?

    init(model: ClipboardHistoryModel, onRestore: @escaping (ClipboardItem) -> Void) {
        self.model = model
        self.onRestore = onRestore
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func loadView() {
        let effect = FloatingPanelRootView(frame: NSRect(origin: .zero, size: Self.panelSize))
        view = effect
        configureSearch()
        configureTable()
        contentStack.orientation = .horizontal
        contentStack.spacing = 0
        contentStack.addArrangedSubview(scrollView)
        contentStack.addArrangedSubview(imagePreview)
        status.setAccessibilityIdentifier("clipboard.status")
        [headerView, contentStack, footerView].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            effect.addSubview($0)
        }
        NSLayoutConstraint.activate([
            headerView.topAnchor.constraint(equalTo: effect.topAnchor),
            headerView.leadingAnchor.constraint(equalTo: effect.leadingAnchor),
            headerView.trailingAnchor.constraint(equalTo: effect.trailingAnchor),
            contentStack.topAnchor.constraint(equalTo: headerView.bottomAnchor, constant: 6),
            contentStack.leadingAnchor.constraint(equalTo: effect.leadingAnchor),
            contentStack.trailingAnchor.constraint(equalTo: effect.trailingAnchor),
            contentStack.bottomAnchor.constraint(equalTo: footerView.topAnchor, constant: -6),
            footerView.leadingAnchor.constraint(equalTo: effect.leadingAnchor),
            footerView.trailingAnchor.constraint(equalTo: effect.trailingAnchor),
            footerView.bottomAnchor.constraint(equalTo: effect.bottomAnchor),
        ])
        render()
    }

    func focusSearchField() {
        _ = view
        searchField.stringValue = ""
        model.resetToLatest()
        render()
        view.window?.makeFirstResponder(searchField)
    }

    func updateItems(_ items: [ClipboardItem]) {
        model.updateItems(items)
        render()
    }

    private func configureSearch() {
        searchField.placeholderString = L10n.tr("clipboard.search_placeholder")
        searchField.delegate = self
        searchField.setAccessibilityLabel(L10n.tr("clipboard.search_accessibility"))
        searchField.setAccessibilityIdentifier("clipboard.query")
    }

    private func configureTable() {
        FloatingPanelChrome.configureResultsTable(
            tableView,
            in: scrollView,
            columnIdentifier: "clipboard.result",
            width: Self.panelSize.width,
            accessibilityLabel: L10n.tr("clipboard.results_accessibility")
        )
        tableView.dataSource = self
        tableView.delegate = self
        tableView.target = self
        tableView.doubleAction = #selector(restoreSelected)
    }

    private func render() {
        guard isViewLoaded else { return }
        rendering = true
        defer { rendering = false }
        status.stringValue = model.message
        imagePreview.update(with: model.selectedItem)
        updateHeaderBadge()
        tableView.reloadData()
        if let index = model.visibleItems.firstIndex(where: { $0.id == model.selectedID }) {
            tableView.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
            tableView.scrollRowToVisible(index)
        } else {
            tableView.deselectAll(nil)
        }
        let contentHeight = PennyworthTheme.collapsedPanelHeight
            + CGFloat(min(max(model.visibleItems.count, 1), 7)) * PennyworthTheme.rowHeight
        onHeightChanged?(imagePreview.isHidden ? contentHeight : max(contentHeight, Self.imagePreviewPanelHeight))
    }

    @objc private func restoreSelected() {
        guard let item = model.selectedItem else { return }
        onRestore(item)
    }

    private func updateHeaderBadge() {
        guard let selected = model.selectedItem else {
            headerView.badge.update(text: "", style: .neutral)
            return
        }
        let label: String
        switch selected.content {
        case .text: label = L10n.tr("clipboard.badge.text")
        case .image: label = L10n.tr("clipboard.badge.image")
        case .file: label = L10n.tr("clipboard.badge.file")
        }
        headerView.badge.update(text: label, style: .accent)
    }

    private func result(for item: ClipboardItem) -> SearchResult {
        let action: SearchAction
        let symbol: String
        switch item.content {
        case .text(let text):
            action = .copyText(text)
            symbol = "doc.on.clipboard"
        case .image:
            action = .copyText("")
            symbol = "photo"
        case .file(let url):
            action = .openFile(url)
            symbol = "doc"
        }
        return SearchResult(id: "clipboard:\(item.id.uuidString)", title: item.displayTitle,
                            subtitle: item.displaySubtitle, symbol: symbol, action: action)
    }
}

extension ClipboardHistoryViewController: NSTextFieldDelegate {
    func controlTextDidChange(_ notification: Notification) {
        if let editor = searchField.currentEditor() as? NSTextView, editor.hasMarkedText() { return }
        model.updateQuery(searchField.stringValue)
        render()
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        guard !textView.hasMarkedText() else { return false }
        switch selector {
        case #selector(NSResponder.moveDown(_:)): model.moveSelection(by: 1)
        case #selector(NSResponder.moveUp(_:)): model.moveSelection(by: -1)
        case #selector(NSResponder.insertNewline(_:)): restoreSelected()
        case #selector(NSResponder.cancelOperation(_:)): onDismiss?()
        default: return false
        }
        render()
        return true
    }
}

extension ClipboardHistoryViewController: NSTableViewDataSource, NSTableViewDelegate {
    func numberOfRows(in tableView: NSTableView) -> Int { model.visibleItems.count }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard !rendering, model.visibleItems.indices.contains(tableView.selectedRow) else { return }
        model.select(model.visibleItems[tableView.selectedRow].id)
        render()
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let item = model.visibleItems[row]
        let result = result(for: item)
        let identifier = NSUserInterfaceItemIdentifier("ClipboardResultCell")
        let cell = (tableView.makeView(withIdentifier: identifier, owner: nil) as? ResultCellView)
            ?? ResultCellView(identifier: identifier)
        let icon: NSImage?
        let usesSymbolBackground: Bool
        if case .image(let image, _) = item.content {
            icon = image
            usesSymbolBackground = false
        } else {
            icon = NSImage(systemSymbolName: result.symbol, accessibilityDescription: nil)
            usesSymbolBackground = true
        }
        cell.configure(
            result,
            icon: icon,
            selected: item.id == model.selectedID,
            usesSymbolBackground: usesSymbolBackground,
            actionBadgeText: L10n.tr("clipboard.keycap.restore")
        )
        return cell
    }
}
