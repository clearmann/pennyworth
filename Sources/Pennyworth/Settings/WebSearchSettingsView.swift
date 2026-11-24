import AppKit

/// Card-based list of built-in and custom keyword web searches with inline switches and sheet editing.
@MainActor final class WebSearchSettingsView: NSView {
    private let listCard = SettingsCardView()
    private(set) var definitions: [WebSearchDefinition] = []
    private var activeSheet: WebSearchEditorSheet?

    var onCommitDefinitions: (([WebSearchDefinition]) -> Result<Void, Error>)?

    init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        addSubview(listCard)
        NSLayoutConstraint.activate([
            listCard.leadingAnchor.constraint(equalTo: leadingAnchor),
            listCard.trailingAnchor.constraint(equalTo: trailingAnchor),
            listCard.topAnchor.constraint(equalTo: topAnchor),
            listCard.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func reload(_ definitions: [WebSearchDefinition]) {
        self.definitions = definitions
        rebuildRows()
    }

    @objc func presentAddSheet() {
        presentSheet(editing: nil)
    }

    private func presentSheet(editing: WebSearchDefinition?) {
        guard let window, activeSheet == nil else { return }
        let sheet = WebSearchEditorSheet(
            editing: editing,
            onCommit: { [weak self] candidate in
                guard let self else { return .success(()) }
                let updated: [WebSearchDefinition]
                if let editing, let idx = self.definitions.firstIndex(where: { $0.id == editing.id }) {
                    updated = self.definitions.enumerated().map { $0.offset == idx ? candidate : $0.element }
                } else {
                    updated = self.definitions + [candidate]
                }
                let result = self.onCommitDefinitions?(updated) ?? .success(())
                if case .success = result {
                    self.definitions = updated
                    self.rebuildRows()
                }
                return result
            },
            onDismiss: { [weak self] in
                self?.activeSheet = nil
            }
        )
        activeSheet = sheet
        sheet.present(on: window)
    }

    private func rebuildRows() {
        let rows = definitions.map { buildRow(for: $0) }
        listCard.setRows(rows)
    }

    private func buildRow(for definition: WebSearchDefinition) -> NSView {
        let keywordBadge = SettingsBadgeLabel(
            text: definition.keyword,
            tone: definition.isCustom ? .accent : .neutral,
            monospaced: true,
            minWidth: 82
        )

        let titleBadges: [NSView] = definition.isCustom
            ? [SettingsBadgeLabel(text: L10n.tr("web_search.custom"), tone: .accent)]
            : []

        var trailing: [NSView] = []
        if definition.isCustom {
            let editButton = SettingsIconButton(
                symbolName: "pencil",
                accessibilityLabel: L10n.format("web_search.row.edit_accessibility", definition.title),
                tooltip: L10n.tr("common.edit"),
                target: self,
                action: #selector(editCustomSearch(_:))
            )
            editButton.identifier = NSUserInterfaceItemIdentifier(definition.id)

            let deleteButton = SettingsIconButton(
                symbolName: "trash",
                accessibilityLabel: L10n.format("web_search.row.delete_accessibility", definition.title),
                tooltip: L10n.tr("common.delete"),
                isDestructive: true,
                target: self,
                action: #selector(deleteCustomSearch(_:))
            )
            deleteButton.identifier = NSUserInterfaceItemIdentifier(definition.id)
            trailing.append(contentsOf: [editButton, deleteButton])
        }

        let toggle = NSSwitch()
        toggle.controlSize = .small
        toggle.state = definition.isEnabled ? .on : .off
        toggle.identifier = NSUserInterfaceItemIdentifier(definition.id)
        toggle.target = self
        toggle.action = #selector(toggleDefinition(_:))
        toggle.setAccessibilityLabel(L10n.format("web_search.row.toggle_accessibility", definition.title))
        trailing.append(toggle)

        return SettingsRowView(
            title: definition.title,
            subtitle: definition.urlTemplate,
            leadingView: keywordBadge,
            trailingViews: trailing,
            titleBadges: titleBadges,
            dimmed: !definition.isEnabled
        )
    }

    @objc private func editCustomSearch(_ sender: NSButton) {
        guard let id = sender.identifier?.rawValue,
              let target = definitions.first(where: { $0.id == id && $0.isCustom }) else { return }
        presentSheet(editing: target)
    }

    @objc private func deleteCustomSearch(_ sender: NSButton) {
        guard let id = sender.identifier?.rawValue,
              let target = definitions.first(where: { $0.id == id && $0.isCustom }) else { return }
        let updated = definitions.filter { $0.id != target.id }
        let result = onCommitDefinitions?(updated) ?? .success(())
        if case .success = result {
            definitions = updated
            rebuildRows()
        }
    }

    @objc private func toggleDefinition(_ sender: NSSwitch) {
        guard let id = sender.identifier?.rawValue,
              let index = definitions.firstIndex(where: { $0.id == id }) else { return }
        let current = definitions[index]
        let replacement = WebSearchDefinition(
            id: current.id,
            keyword: current.keyword,
            title: current.title,
            urlTemplate: current.urlTemplate,
            isEnabled: sender.state == .on,
            isCustom: current.isCustom
        )
        let updated = definitions.enumerated().map { $0.offset == index ? replacement : $0.element }
        let result = onCommitDefinitions?(updated) ?? .success(())
        switch result {
        case .success:
            definitions = updated
            rebuildRows()
        case .failure:
            sender.state = current.isEnabled ? .on : .off
        }
    }
}
