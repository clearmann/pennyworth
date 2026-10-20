import AppKit

/// AppKit presentation; search and execution state live in LauncherModel.
@MainActor final class LauncherViewController: NSViewController {
    static let panelSize = NSSize(width: 680, height: 420)
    private let model: LauncherModel
    private let searchField = NSTextField()
    private let tableView = NSTableView()
    private let status = NSTextField(labelWithString: "")
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
        let effect = NSVisualEffectView(frame: NSRect(origin: .zero, size: Self.panelSize))
        effect.material = .popover
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 14
        effect.layer?.masksToBounds = true
        view = effect
        configureSearch()
        configureTable()
        status.font = .systemFont(ofSize: 12)
        status.textColor = .secondaryLabelColor
        status.lineBreakMode = .byTruncatingTail
        status.setAccessibilityIdentifier("launcher.status")
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

    private func configureSearch() {
        searchField.font = .systemFont(ofSize: 26, weight: .light)
        searchField.isBezeled = false
        searchField.drawsBackground = false
        searchField.focusRingType = .none
        searchField.placeholderString = "搜索应用，空格搜索文件…"
        searchField.delegate = self
        searchField.setAccessibilityLabel("搜索")
        searchField.setAccessibilityIdentifier("launcher.query")
    }

    private func configureTable() {
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("result"))
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
        tableView.doubleAction = #selector(execute)
        tableView.setAccessibilityLabel("搜索结果")
        scrollView.documentView = tableView
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
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
        status.stringValue = model.isExecuting ? "正在执行…" : model.snapshot.message
        tableView.reloadData()
        if let index = model.snapshot.results.firstIndex(where: { $0.id == model.selectedID }) {
            tableView.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
            tableView.scrollRowToVisible(index)
        } else { tableView.deselectAll(nil) }
        onHeightChanged?(106 + CGFloat(min(max(model.snapshot.results.count, 1), 7)) * 56)
    }

    @objc private func execute() { model.executeSelected() }
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
        cell.configure(result, icon: icon, selected: result.id == model.selectedID)
        return cell
    }
}

final class ResultCellView: NSTableCellView {
    private let subtitle = NSTextField(labelWithString: "")
    private let hint = NSTextField(labelWithString: "↵")

    init(identifier: NSUserInterfaceItemIdentifier) {
        super.init(frame: .zero)
        self.identifier = identifier
        let image = NSImageView()
        let title = NSTextField(labelWithString: "")
        title.font = .systemFont(ofSize: 15, weight: .medium)
        subtitle.font = .systemFont(ofSize: 12)
        subtitle.textColor = .secondaryLabelColor
        title.lineBreakMode = .byTruncatingTail
        subtitle.lineBreakMode = .byTruncatingMiddle
        hint.textColor = .secondaryLabelColor
        [image, title, subtitle, hint].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            addSubview($0)
        }
        NSLayoutConstraint.activate([
            image.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 18),
            image.centerYAnchor.constraint(equalTo: centerYAnchor),
            image.widthAnchor.constraint(equalToConstant: 32), image.heightAnchor.constraint(equalToConstant: 32),
            title.leadingAnchor.constraint(equalTo: image.trailingAnchor, constant: 12),
            title.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            title.trailingAnchor.constraint(equalTo: hint.leadingAnchor, constant: -12),
            subtitle.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            subtitle.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 3),
            subtitle.trailingAnchor.constraint(equalTo: title.trailingAnchor),
            hint.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
            hint.centerYAnchor.constraint(equalTo: centerYAnchor), hint.widthAnchor.constraint(equalToConstant: 20),
        ])
        imageView = image
        textField = title
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func configure(_ result: SearchResult, icon: NSImage?, selected: Bool) {
        textField?.stringValue = result.title
        subtitle.stringValue = result.subtitle
        imageView?.image = icon
        hint.isHidden = !selected
        setAccessibilityLabel("\(result.title)，\(result.subtitle)")
    }
}
