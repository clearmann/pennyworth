import AppKit

/// Card-based list of Spotlight file search directories replacing the old pop-up menu selector.
@MainActor final class FileSearchSettingsView: NSView {
    private let listCard = SettingsCardView()
    private(set) var directories: [String] = []

    var onAddRequested: (() -> Void)?
    var onRemoveDirectory: ((String) -> Void)?

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
        rebuildRows()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func reload(_ directories: [String]) {
        self.directories = directories
        rebuildRows()
    }

    private func rebuildRows() {
        if directories.isEmpty {
            let empty = SettingsEmptyStateView(
                symbolName: "folder.badge.plus",
                title: L10n.tr("settings.file_search.empty.title"),
                subtitle: L10n.tr("settings.file_search.empty.subtitle"),
                actionTitle: L10n.tr("settings.add_directory"),
                target: self,
                action: #selector(addClicked)
            )
            listCard.setRows([empty])
            return
        }

        let rows = directories.map { path -> NSView in
            let iconView = NSImageView(image: SettingsStyle.folderIcon(forPath: path))
            iconView.imageScaling = .scaleProportionallyUpOrDown
            iconView.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                iconView.widthAnchor.constraint(equalToConstant: 26),
                iconView.heightAnchor.constraint(equalToConstant: 26),
            ])

            let displayName = FileManager.default.displayName(atPath: path)
            let fallbackName = URL(fileURLWithPath: path).lastPathComponent
            let title = displayName.isEmpty ? (fallbackName.isEmpty ? path : fallbackName) : displayName

            let removeButton = SettingsIconButton(
                symbolName: "trash",
                accessibilityLabel: L10n.format("settings.file_search.remove_accessibility", path),
                tooltip: L10n.tr("common.delete"),
                isDestructive: true,
                target: self,
                action: #selector(removeClicked(_:))
            )
            removeButton.identifier = NSUserInterfaceItemIdentifier(path)

            return SettingsRowView(
                title: title,
                subtitle: SettingsStyle.abbreviatedPath(path),
                leadingView: iconView,
                trailingViews: [removeButton]
            )
        }
        listCard.setRows(rows)
    }

    @objc private func addClicked() {
        onAddRequested?()
    }

    @objc private func removeClicked(_ sender: NSButton) {
        guard let path = sender.identifier?.rawValue else { return }
        onRemoveDirectory?(path)
    }
}
