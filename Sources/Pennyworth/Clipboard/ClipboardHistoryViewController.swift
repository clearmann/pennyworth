import AppKit

@MainActor final class ClipboardHistoryViewController: NSViewController {
    static let panelSize = NSSize(width: 680, height: 420)

    private let model: ClipboardHistoryModel
    private let onRestore: (ClipboardItem) -> Void
    private let searchField = NSTextField()
    private let tableView = NSTableView()
    private let status = NSTextField(labelWithString: "")
    private let scrollView = NSScrollView()
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
        let effect = NSVisualEffectView(frame: NSRect(origin: .zero, size: Self.panelSize))
        effect.material = .popover
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 14
        view = effect
        configureSearch()
        configureTable()
        status.font = .systemFont(ofSize: 12)
        status.textColor = .secondaryLabelColor
        status.lineBreakMode = .byTruncatingTail
        status.setAccessibilityIdentifier("clipboard.status")
        [searchField, scrollView, status].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            effect.addSubview($0)
        }
        NSLayoutConstraint.activate([
            searchField.leadingAnchor.constraint(equalTo: effect.leadingAnchor, constant: 18),
            searchField.trailingAnchor.constraint(equalTo: effect.trailingAnchor, constant: -18),
            searchField.topAnchor.constraint(equalTo: effect.topAnchor, constant: 12),
            searchField.heightAnchor.constraint(equalToConstant: 48),
            scrollView.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 8),
            scrollView.leadingAnchor.constraint(equalTo: effect.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: effect.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: status.topAnchor, constant: -8),
            status.leadingAnchor.constraint(equalTo: effect.leadingAnchor, constant: 18),
            status.trailingAnchor.constraint(equalTo: effect.trailingAnchor, constant: -18),
            status.bottomAnchor.constraint(equalTo: effect.bottomAnchor, constant: -10),
            status.heightAnchor.constraint(equalToConstant: 20),
        ])
        render()
    }

    func focusSearchField() {
        _ = view
        searchField.stringValue = ""
        model.updateQuery("")
        render()
        view.window?.makeFirstResponder(searchField)
    }

    func updateItems(_ items: [ClipboardItem]) {
        model.updateItems(items)
        render()
    }

    private func configureSearch() {
        searchField.font = .systemFont(ofSize: 26, weight: .light)
        searchField.isBezeled = false
        searchField.drawsBackground = false
        searchField.focusRingType = .none
        searchField.placeholderString = "搜索剪贴板历史…"
        searchField.delegate = self
        searchField.setAccessibilityLabel("剪贴板历史搜索")
        searchField.setAccessibilityIdentifier("clipboard.query")
    }

    private func configureTable() {
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("clipboard.result"))
        column.width = Self.panelSize.width
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.rowHeight = 56
        tableView.intercellSpacing = .zero
        tableView.backgroundColor = .clear
        tableView.style = .fullWidth
        tableView.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        tableView.dataSource = self
        tableView.delegate = self
        tableView.target = self
        tableView.doubleAction = #selector(restoreSelected)
        tableView.setAccessibilityLabel("剪贴板历史结果")
        scrollView.documentView = tableView
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
    }

    private func render() {
        guard isViewLoaded else { return }
        rendering = true
        defer { rendering = false }
        status.stringValue = model.message
        tableView.reloadData()
        if let index = model.visibleItems.firstIndex(where: { $0.id == model.selectedID }) {
            tableView.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
            tableView.scrollRowToVisible(index)
        } else {
            tableView.deselectAll(nil)
        }
        onHeightChanged?(106 + CGFloat(min(max(model.visibleItems.count, 1), 7)) * 56)
    }

    @objc private func restoreSelected() {
        guard let item = model.selectedItem else { return }
        onRestore(item)
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
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let item = model.visibleItems[row]
        let result = result(for: item)
        let identifier = NSUserInterfaceItemIdentifier("ClipboardResultCell")
        let cell = (tableView.makeView(withIdentifier: identifier, owner: nil) as? ResultCellView)
            ?? ResultCellView(identifier: identifier)
        cell.configure(result, icon: NSImage(systemSymbolName: result.symbol, accessibilityDescription: nil),
                       selected: item.id == model.selectedID)
        return cell
    }
}
