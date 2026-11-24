import AppKit

/// Card-based list of per-application global shortcuts with inline recording, switches, and deletion.
@MainActor final class AppShortcutsSettingsView: NSView {
    private let listCard = SettingsCardView()
    private var availableApps: [AppItem] = []
    private(set) var shortcuts: [AppShortcut] = []
    private var activeSheet: AppShortcutEditorSheet?

    var onRecordingStateChanged: ((Bool) -> Void)?
    var onCommitShortcuts: (([AppShortcut]) -> Result<Void, Error>)?

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

    func reload(_ shortcuts: [AppShortcut], availableApps: [AppItem]) {
        self.availableApps = availableApps
        self.shortcuts = shortcuts
        rebuildRows()
    }

    func updateAvailableApps(_ apps: [AppItem]) {
        availableApps = apps
    }

    @objc func presentAddSheet() {
        guard let window, activeSheet == nil else { return }
        let existingPaths = Set(shortcuts.map(\.appPath))
        let sheet = AppShortcutEditorSheet(
            availableApps: availableApps,
            existingPaths: existingPaths,
            onRecordingStateChanged: { [weak self] recording in
                self?.onRecordingStateChanged?(recording)
            },
            onCommit: { [weak self] created in
                guard let self else { return .success(()) }
                let updated = self.shortcuts + [created]
                let result = self.onCommitShortcuts?(updated) ?? .success(())
                if case .success = result {
                    self.shortcuts = updated
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
        if shortcuts.isEmpty {
            let empty = SettingsEmptyStateView(
                symbolName: "command",
                title: L10n.tr("app_shortcuts.empty.title"),
                subtitle: L10n.tr("app_shortcuts.empty.subtitle"),
                actionTitle: L10n.tr("app_shortcuts.add"),
                target: self,
                action: #selector(presentAddSheet)
            )
            listCard.setRows([empty])
            return
        }

        let rows = shortcuts.map { buildRow(for: $0) }
        listCard.setRows(rows)
    }

    private func buildRow(for shortcut: AppShortcut) -> NSView {
        let iconView = NSImageView(image: SettingsStyle.applicationIcon(forPath: shortcut.appPath))
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            iconView.widthAnchor.constraint(equalToConstant: 32),
            iconView.heightAnchor.constraint(equalToConstant: 32),
        ])
        iconView.alphaValue = shortcut.isEnabled ? 1.0 : 0.45

        let recorder = HotKeyRecorderView(binding: shortcut.hotKey, allowsClearing: false, compact: true)
        recorder.setAccessibilityLabel(L10n.format("app_shortcuts.row.hotkey_accessibility", shortcut.appName))
        recorder.onRecordingStateChanged = { [weak self] recording in
            self?.onRecordingStateChanged?(recording)
        }
        recorder.onChange = { [weak self, weak recorder] nextHotKey in
            guard let self, let nextHotKey else { return }
            self.updateHotKey(forID: shortcut.id, to: nextHotKey, recorder: recorder)
        }

        let toggle = NSSwitch()
        toggle.controlSize = .small
        toggle.state = shortcut.isEnabled ? .on : .off
        toggle.identifier = NSUserInterfaceItemIdentifier(shortcut.id)
        toggle.target = self
        toggle.action = #selector(toggleShortcut(_:))
        toggle.setAccessibilityLabel(L10n.format("app_shortcuts.row.toggle_accessibility", shortcut.appName))

        let deleteButton = SettingsIconButton(
            symbolName: "trash",
            accessibilityLabel: L10n.format("app_shortcuts.row.delete_accessibility", shortcut.appName),
            tooltip: L10n.tr("common.delete"),
            isDestructive: true,
            target: self,
            action: #selector(deleteShortcut(_:))
        )
        deleteButton.identifier = NSUserInterfaceItemIdentifier(shortcut.id)

        return SettingsRowView(
            title: shortcut.appName,
            subtitle: SettingsStyle.abbreviatedPath(shortcut.appPath),
            leadingView: iconView,
            trailingViews: [recorder, toggle, deleteButton],
            dimmed: !shortcut.isEnabled
        )
    }

    private func updateHotKey(forID id: String, to hotKey: HotKeyPreset, recorder: HotKeyRecorderView?) {
        guard let index = shortcuts.firstIndex(where: { $0.id == id }) else { return }
        let current = shortcuts[index]
        guard current.hotKey != hotKey else { return }
        let replacement = AppShortcut(
            id: current.id,
            bundleIdentifier: current.bundleIdentifier,
            appPath: current.appPath,
            appName: current.appName,
            hotKey: hotKey,
            isEnabled: current.isEnabled
        )
        let next = shortcuts.enumerated().map { $0.offset == index ? replacement : $0.element }
        let result = onCommitShortcuts?(next) ?? .success(())
        switch result {
        case .success:
            shortcuts = next
        case .failure:
            recorder?.setBinding(current.hotKey)
        }
    }

    @objc private func toggleShortcut(_ sender: NSSwitch) {
        guard let id = sender.identifier?.rawValue,
              let index = shortcuts.firstIndex(where: { $0.id == id }) else { return }
        let current = shortcuts[index]
        let nextEnabled = sender.state == .on
        let replacement = AppShortcut(
            id: current.id,
            bundleIdentifier: current.bundleIdentifier,
            appPath: current.appPath,
            appName: current.appName,
            hotKey: current.hotKey,
            isEnabled: nextEnabled
        )
        let next = shortcuts.enumerated().map { $0.offset == index ? replacement : $0.element }
        let result = onCommitShortcuts?(next) ?? .success(())
        switch result {
        case .success:
            shortcuts = next
            rebuildRows()
        case .failure:
            sender.state = current.isEnabled ? .on : .off
        }
    }

    @objc private func deleteShortcut(_ sender: NSButton) {
        guard let id = sender.identifier?.rawValue else { return }
        let next = shortcuts.filter { $0.id != id }
        let result = onCommitShortcuts?(next) ?? .success(())
        if case .success = result {
            shortcuts = next
            rebuildRows()
        }
    }
}
