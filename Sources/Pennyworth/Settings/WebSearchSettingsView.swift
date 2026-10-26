import AppKit

@MainActor final class WebSearchSettingsView: NSView {
    private let tableView = NSTableView()
    private let keywordField = NSTextField()
    private let titleField = NSTextField()
    private let templateField = NSTextField()
    private let addButton = NSButton(title: "添加自定义搜索", target: nil, action: nil)
    private let removeButton = NSButton(title: "删除自定义搜索", target: nil, action: nil)
    private let enabledButton = NSButton(checkboxWithTitle: "启用", target: nil, action: nil)
    private(set) var definitions: [WebSearchDefinition] = []

    init() {
        super.init(frame: .zero)
        configure()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func reload(_ definitions: [WebSearchDefinition]) {
        self.definitions = definitions
        tableView.reloadData()
        selectDefinition(at: definitions.isEmpty ? -1 : 0)
    }

    private func configure() {
        translatesAutoresizingMaskIntoConstraints = false
        configureTable()
        configureEditor()
        addButton.target = self
        addButton.action = #selector(addCustomSearch)
        removeButton.target = self
        removeButton.action = #selector(removeCustomSearch)
        enabledButton.target = self
        enabledButton.action = #selector(toggleEnabled)
        enabledButton.setAccessibilityLabel("启用所选网页搜索")
        let actions = NSStackView(views: [addButton, removeButton, enabledButton])
        actions.spacing = 12
        actions.translatesAutoresizingMaskIntoConstraints = false
        addSubview(actions)
        let scroll = tableView.enclosingScrollView!
        let editor = editorStack()
        editor.translatesAutoresizingMaskIntoConstraints = false
        addSubview(editor)
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: trailingAnchor),
            scroll.topAnchor.constraint(equalTo: topAnchor),
            scroll.heightAnchor.constraint(equalToConstant: 176),
            editor.leadingAnchor.constraint(equalTo: leadingAnchor),
            editor.topAnchor.constraint(equalTo: scroll.bottomAnchor, constant: 14),
            actions.leadingAnchor.constraint(equalTo: leadingAnchor),
            actions.topAnchor.constraint(equalTo: editor.bottomAnchor, constant: 12),
            actions.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        for field in [keywordField, titleField, templateField] {
            field.widthAnchor.constraint(equalTo: widthAnchor, constant: -104).isActive = true
        }
    }

    private func configureTable() {
        for (id, title, width) in [
            ("keyword", "关键词", 70.0),
            ("title", "显示名称", 86.0),
            ("template", "搜索 URL", 220.0),
            ("source", "来源", 50.0),
            ("enabled", "启用", 44.0),
        ] {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id))
            column.title = title
            column.width = width
            tableView.addTableColumn(column)
        }
        tableView.dataSource = self
        tableView.delegate = self
        tableView.rowHeight = 24
        tableView.intercellSpacing = NSSize(width: 4, height: 2)
        tableView.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        tableView.allowsMultipleSelection = false
        tableView.setAccessibilityLabel("网页搜索列表")
        let scroll = NSScrollView()
        scroll.documentView = tableView
        scroll.hasVerticalScroller = true
        scroll.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scroll)
    }

    private func configureEditor() {
        for (field, label) in [
            (keywordField, "网页搜索关键词"),
            (titleField, "网页搜索显示名称"),
            (templateField, "网页搜索 URL 模板"),
        ] {
            field.delegate = self
            field.setAccessibilityLabel(label)
            field.lineBreakMode = .byTruncatingMiddle
        }
        keywordField.placeholderString = "例如 gh"
        titleField.placeholderString = "例如 GitHub"
        templateField.placeholderString = "https://github.com/search?q={query}"
    }

    private func editorStack() -> NSStackView {
        let rows = [keywordField, titleField, templateField].map { field -> NSStackView in
            let label = NSTextField(labelWithString: field == keywordField ? "关键词" : field == titleField ? "显示名称" : "搜索 URL")
            label.widthAnchor.constraint(equalToConstant: 88).isActive = true
            let row = NSStackView(views: [label, field])
            row.spacing = 8
            return row
        }
        let stack = NSStackView(views: rows)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        return stack
    }

    private func selectDefinition(at index: Int) {
        if definitions.indices.contains(index) {
            tableView.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
            tableView.scrollRowToVisible(index)
        } else {
            tableView.deselectAll(nil)
        }
        updateEditor()
    }

    private func updateEditor() {
        guard definitions.indices.contains(tableView.selectedRow) else {
            for field in [keywordField, titleField, templateField] {
                field.stringValue = ""
                field.isEditable = false
            }
            removeButton.isEnabled = false
            enabledButton.isEnabled = false
            return
        }
        let definition = definitions[tableView.selectedRow]
        keywordField.stringValue = definition.keyword
        titleField.stringValue = definition.title
        templateField.stringValue = definition.urlTemplate
        for field in [keywordField, titleField, templateField] { field.isEditable = definition.isCustom }
        removeButton.isEnabled = definition.isCustom
        enabledButton.isEnabled = true
        enabledButton.state = definition.isEnabled ? .on : .off
    }

    private func replaceSelected(with updated: WebSearchDefinition) {
        let index = tableView.selectedRow
        guard definitions.indices.contains(index) else { return }
        definitions = definitions.enumerated().map { $0.offset == index ? updated : $0.element }
        tableView.reloadData(forRowIndexes: IndexSet(integer: index),
                             columnIndexes: IndexSet(integersIn: 0..<tableView.numberOfColumns))
    }

    @objc private func addCustomSearch() {
        let custom = WebSearchDefinition(
            id: "custom.\(UUID().uuidString)", keyword: "", title: "", urlTemplate: ""
        )
        definitions = definitions + [custom]
        tableView.reloadData()
        selectDefinition(at: definitions.count - 1)
        window?.makeFirstResponder(keywordField)
    }

    @objc private func toggleEnabled() {
        guard definitions.indices.contains(tableView.selectedRow) else { return }
        let current = definitions[tableView.selectedRow]
        replaceSelected(with: WebSearchDefinition(
            id: current.id, keyword: current.keyword, title: current.title, urlTemplate: current.urlTemplate,
            isEnabled: enabledButton.state == .on, isCustom: current.isCustom
        ))
    }

    @objc private func removeCustomSearch() {
        let index = tableView.selectedRow
        guard definitions.indices.contains(index), definitions[index].isCustom else { return }
        definitions = definitions.enumerated().filter { $0.offset != index }.map(\.element)
        tableView.reloadData()
        selectDefinition(at: min(index, definitions.count - 1))
    }
}

extension WebSearchSettingsView: NSTableViewDataSource, NSTableViewDelegate {
    func numberOfRows(in tableView: NSTableView) -> Int { definitions.count }

    func tableViewSelectionDidChange(_ notification: Notification) { updateEditor() }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard definitions.indices.contains(row), let id = tableColumn?.identifier.rawValue else { return nil }
        let definition = definitions[row]
        let text: String
        switch id {
        case "keyword": text = definition.keyword
        case "title": text = definition.title
        case "template": text = definition.urlTemplate
        case "source": text = definition.isCustom ? "自定义" : "内置"
        case "enabled": text = definition.isEnabled ? "是" : "否"
        default: return nil
        }
        let cell = NSTextField(labelWithString: text)
        cell.lineBreakMode = .byTruncatingMiddle
        return cell
    }
}

extension WebSearchSettingsView: NSTextFieldDelegate {
    func controlTextDidChange(_ notification: Notification) {
        guard definitions.indices.contains(tableView.selectedRow) else { return }
        let current = definitions[tableView.selectedRow]
        guard current.isCustom else { return }
        let updated = WebSearchDefinition(
            id: current.id,
            keyword: notification.object as? NSTextField === keywordField ? keywordField.stringValue : current.keyword,
            title: notification.object as? NSTextField === titleField ? titleField.stringValue : current.title,
            urlTemplate: notification.object as? NSTextField === templateField ? templateField.stringValue : current.urlTemplate,
            isEnabled: current.isEnabled,
            isCustom: current.isCustom
        )
        replaceSelected(with: updated)
    }
}
