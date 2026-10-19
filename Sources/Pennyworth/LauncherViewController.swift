import AppKit

/// The search UI: one big text field on top, result list below.
final class LauncherViewController: NSViewController {
    static let panelSize = NSSize(width: 680, height: 420)

    private enum Layout {
        static let searchFieldHeight: CGFloat = 52
        static let rowHeight: CGFloat = 44
        static let edgePadding: CGFloat = 12
        static let iconSize: CGFloat = 32
    }

    private let searchField = NSTextField()
    private let tableView = NSTableView()

    private let allItems: [AppItem]
    private var visibleItems: [AppItem]

    /// Called when the panel should close (item launched, Esc pressed).
    var onDismiss: (() -> Void)?

    init(items: [AppItem]) {
        self.allItems = items
        self.visibleItems = items
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    // MARK: - View construction

    override func loadView() {
        let effectView = NSVisualEffectView()
        effectView.material = .popover
        effectView.state = .active
        effectView.wantsLayer = true
        effectView.layer?.cornerRadius = 12
        effectView.layer?.masksToBounds = true

        configureSearchField()
        configureTableView()

        let scrollView = NSScrollView()
        scrollView.documentView = tableView
        scrollView.drawsBackground = false
        scrollView.automaticallyAdjustsContentInsets = false

        effectView.addSubview(searchField)
        effectView.addSubview(scrollView)

        let size = Self.panelSize
        searchField.frame = NSRect(
            x: Layout.edgePadding,
            y: size.height - Layout.searchFieldHeight - 8,
            width: size.width - Layout.edgePadding * 2,
            height: Layout.searchFieldHeight
        )
        searchField.autoresizingMask = [.width, .minYMargin]

        scrollView.frame = NSRect(
            x: 0,
            y: 0,
            width: size.width,
            height: size.height - Layout.searchFieldHeight - 16
        )
        scrollView.autoresizingMask = [.width, .height]

        view = effectView
    }

    private func configureSearchField() {
        searchField.font = .systemFont(ofSize: 26, weight: .light)
        searchField.isBezeled = false
        searchField.drawsBackground = false
        searchField.focusRingType = .none
        searchField.placeholderString = "Search apps…"
        searchField.delegate = self
    }

    private func configureTableView() {
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("app"))
        column.width = Self.panelSize.width
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.rowHeight = Layout.rowHeight
        tableView.intercellSpacing = NSSize(width: 0, height: 2)
        tableView.backgroundColor = .clear
        tableView.style = .sourceList
        tableView.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        tableView.dataSource = self
        tableView.delegate = self
        tableView.target = self
        tableView.doubleAction = #selector(launchSelectedItem)
    }

    /// Public entry point called by AppDelegate every time the panel opens.
    func focusSearchField() {
        resetSearch()
        view.window?.makeFirstResponder(searchField)
    }

    // MARK: - Filtering

    private func applyFilter() {
        let query = searchField.stringValue.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else {
            visibleItems = allItems
            reloadAndSelectFirst()
            return
        }
        visibleItems = allItems
            .compactMap { item in
                FuzzyMatcher.score(item: item, query: query).map { (item, $0) }
            }
            .sorted { $0.1 > $1.1 }
            .map(\.0)
        reloadAndSelectFirst()
    }

    private func reloadAndSelectFirst() {
        tableView.reloadData()
        if !visibleItems.isEmpty {
            tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        }
    }

    private func resetSearch() {
        searchField.stringValue = ""
        visibleItems = allItems
        reloadAndSelectFirst()
    }

    // MARK: - Selection & launching

    private func moveSelection(by delta: Int) {
        guard !visibleItems.isEmpty else { return }
        let next = min(max(tableView.selectedRow + delta, 0), visibleItems.count - 1)
        tableView.selectRowIndexes(IndexSet(integer: next), byExtendingSelection: false)
        tableView.scrollRowToVisible(next)
    }

    @objc private func launchSelectedItem() {
        let row = tableView.selectedRow
        guard visibleItems.indices.contains(row) else { return }
        NSWorkspace.shared.open(visibleItems[row].url)
        onDismiss?()
    }
}

// MARK: - NSTextFieldDelegate

extension LauncherViewController: NSTextFieldDelegate {
    func controlTextDidChange(_ notification: Notification) {
        applyFilter()
    }

    /// Route keys from the search field to the list. Returning true means
    /// "handled here, don't let the text field interpret the key".
    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.moveDown(_:)) {
            moveSelection(by: 1)
            return true
        }
        if commandSelector == #selector(NSResponder.moveUp(_:)) {
            moveSelection(by: -1)
            return true
        }
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            launchSelectedItem()
            return true
        }
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            onDismiss?()
            return true
        }
        return false
    }
}

// MARK: - NSTableViewDataSource / Delegate

extension LauncherViewController: NSTableViewDataSource, NSTableViewDelegate {
    func numberOfRows(in tableView: NSTableView) -> Int {
        visibleItems.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let item = visibleItems[row]
        let identifier = NSUserInterfaceItemIdentifier("AppCell")
        let cell = (tableView.makeView(withIdentifier: identifier, owner: nil) as? NSTableCellView)
            ?? Self.makeCell(identifier: identifier)
        cell.textField?.stringValue = item.name
        cell.imageView?.image = item.icon
        return cell
    }

    private static func makeCell(identifier: NSUserInterfaceItemIdentifier) -> NSTableCellView {
        let cell = NSTableCellView()
        cell.identifier = identifier

        let imageView = NSImageView(frame: NSRect(
            x: Layout.edgePadding,
            y: (Layout.rowHeight - Layout.iconSize) / 2,
            width: Layout.iconSize,
            height: Layout.iconSize
        ))
        imageView.imageScaling = .scaleProportionallyUpOrDown

        let label = NSTextField(labelWithString: "")
        label.font = .systemFont(ofSize: 15)
        label.lineBreakMode = .byTruncatingTail
        label.frame = NSRect(
            x: Layout.edgePadding + Layout.iconSize + 10,
            y: 0,
            width: panelSize.width - Layout.iconSize - 40,
            height: Layout.rowHeight
        )
        label.autoresizingMask = [.width]

        cell.addSubview(imageView)
        cell.addSubview(label)
        cell.imageView = imageView
        cell.textField = label
        return cell
    }
}
