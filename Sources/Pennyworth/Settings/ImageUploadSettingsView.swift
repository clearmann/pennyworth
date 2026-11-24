import AppKit

/// Segmented image-upload settings view organizing Hosts, Preferences, and History into focused tabs.
@MainActor final class ImageUploadSettingsView: NSView {
    enum Tab: Int, CaseIterable {
        case hosts = 0
        case preferences = 1
        case history = 2
    }

    private let tabControl = NSSegmentedControl()
    private let hostsContainer = NSStackView()
    private let preferencesContainer = NSStackView()
    private let historyContainer = NSStackView()

    private let hostsCard = SettingsCardView()
    private let addHostButton: NSButton

    private let formatPopup = NSPopUpButton()
    private let encodeURLSwitch = NSSwitch()
    private let compressSlider = NSSlider(value: 100, minValue: 10, maxValue: 100, target: nil, action: nil)
    private let compressValueBadge = SettingsBadgeLabel(text: "", tone: .neutral, monospaced: true, minWidth: 84)
    private let clipboardHotKeyRecorder = HotKeyRecorderView(binding: nil, allowsClearing: true)
    private let fileHotKeyRecorder = HotKeyRecorderView(binding: nil, allowsClearing: true)

    private let historyCard = SettingsCardView()
    private let clearHistoryButton: NSButton

    private let secretStore: ImageUploadSecretStoring
    private var appliedSettings: ImageUploadSettings = .defaults
    private var historyItems: [UploadHistoryItem] = []
    private var activeSheet: ImageHostEditorSheet?

    var onRecordingStateChanged: ((Bool) -> Void)? {
        didSet {
            clipboardHotKeyRecorder.onRecordingStateChanged = onRecordingStateChanged
            fileHotKeyRecorder.onRecordingStateChanged = onRecordingStateChanged
        }
    }
    var onCommitSettings: ((ImageUploadSettings, (() throws -> Void)?) -> Result<Void, Error>)?
    var onCopyHistoryItem: ((UploadHistoryItem) -> Void)?
    var onClearHistory: (() -> Void)?

    init(secretStore: ImageUploadSecretStoring = KeychainSecretStore()) {
        self.secretStore = secretStore
        self.addHostButton = SettingsStyle.makeButton(
            title: L10n.tr("image_upload.settings.add_host"),
            symbolName: "plus",
            primary: true,
            target: nil,
            action: nil
        )
        self.clearHistoryButton = SettingsStyle.makeButton(
            title: L10n.tr("image_upload.history.clear"),
            symbolName: "trash",
            primary: false,
            target: nil,
            action: nil
        )
        super.init(frame: .zero)
        configure()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func selectTab(_ tab: Tab) {
        tabControl.selectedSegment = tab.rawValue
        updateVisibleTab()
    }

    func reload(_ settings: ImageUploadSettings, history: [UploadHistoryItem]) {
        appliedSettings = settings
        applyPreferencesUI(settings)
        rebuildHostRows()
        reloadHistory(history)
    }

    func reloadHistory(_ items: [UploadHistoryItem]) {
        historyItems = items
        clearHistoryButton.isEnabled = !items.isEmpty
        rebuildHistoryRows()
    }

    private func configure() {
        translatesAutoresizingMaskIntoConstraints = false

        tabControl.segmentCount = Tab.allCases.count
        tabControl.trackingMode = .selectOne
        tabControl.segmentStyle = .rounded
        tabControl.setLabel(L10n.tr("image_upload.tab.hosts"), forSegment: Tab.hosts.rawValue)
        tabControl.setLabel(L10n.tr("image_upload.tab.preferences"), forSegment: Tab.preferences.rawValue)
        tabControl.setLabel(L10n.tr("image_upload.tab.history"), forSegment: Tab.history.rawValue)
        tabControl.selectedSegment = Tab.hosts.rawValue
        tabControl.target = self
        tabControl.action = #selector(tabChanged)
        tabControl.translatesAutoresizingMaskIntoConstraints = false

        configureHostsTab()
        configurePreferencesTab()
        configureHistoryTab()

        let stack = NSStackView(views: [tabControl, hostsContainer, preferencesContainer, historyContainer])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            hostsContainer.widthAnchor.constraint(equalTo: stack.widthAnchor),
            preferencesContainer.widthAnchor.constraint(equalTo: stack.widthAnchor),
            historyContainer.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])

        updateVisibleTab()
        rebuildHostRows()
        rebuildHistoryRows()
    }

    private func configureHostsTab() {
        addHostButton.target = self
        addHostButton.action = #selector(addHostClicked)

        let headerBar = makeHeaderBar(title: L10n.tr("image_upload.section.hosts"), accessory: addHostButton)
        let noteLabel = NSTextField(wrappingLabelWithString: L10n.tr("settings.image_upload.note"))
        noteLabel.font = SettingsStyle.footnoteFont
        noteLabel.textColor = SettingsStyle.secondaryText

        hostsContainer.orientation = .vertical
        hostsContainer.alignment = .leading
        hostsContainer.spacing = 8
        hostsContainer.translatesAutoresizingMaskIntoConstraints = false
        hostsContainer.addArrangedSubview(headerBar)
        hostsContainer.addArrangedSubview(hostsCard)
        hostsContainer.addArrangedSubview(noteLabel)
        NSLayoutConstraint.activate([
            headerBar.widthAnchor.constraint(equalTo: hostsContainer.widthAnchor),
            hostsCard.widthAnchor.constraint(equalTo: hostsContainer.widthAnchor),
            noteLabel.widthAnchor.constraint(equalTo: hostsContainer.widthAnchor),
        ])
    }

    private func configurePreferencesTab() {
        formatPopup.addItems(withTitles: UploadOutputFormat.allCases.map(\.title))
        formatPopup.target = self
        formatPopup.action = #selector(preferencesControlChanged)
        formatPopup.setAccessibilityLabel(L10n.tr("image_upload.settings.output_format"))
        formatPopup.widthAnchor.constraint(equalToConstant: 150).isActive = true

        encodeURLSwitch.controlSize = .small
        encodeURLSwitch.target = self
        encodeURLSwitch.action = #selector(preferencesControlChanged)
        encodeURLSwitch.setAccessibilityLabel(L10n.tr("image_upload.settings.encode_url"))

        compressSlider.numberOfTickMarks = 19
        compressSlider.allowsTickMarkValuesOnly = true
        compressSlider.isContinuous = true
        compressSlider.target = self
        compressSlider.action = #selector(compressSliderChanged)
        compressSlider.setAccessibilityLabel(L10n.tr("image_upload.settings.compress_quality"))
        compressSlider.widthAnchor.constraint(equalToConstant: 164).isActive = true

        let compressControl = NSStackView(views: [compressSlider, compressValueBadge])
        compressControl.orientation = .horizontal
        compressControl.alignment = .centerY
        compressControl.spacing = 10

        clipboardHotKeyRecorder.setAccessibilityLabel(L10n.tr("image_upload.settings.clipboard_hotkey"))
        clipboardHotKeyRecorder.onChange = { [weak self] _ in
            self?.commitPreferencesChange()
        }
        fileHotKeyRecorder.setAccessibilityLabel(L10n.tr("image_upload.settings.file_hotkey"))
        fileHotKeyRecorder.onChange = { [weak self] _ in
            self?.commitPreferencesChange()
        }

        let generalSection = SettingsSectionView(
            title: L10n.tr("image_upload.section.general"),
            rows: [
                SettingsRowView(title: L10n.tr("image_upload.settings.output_format"), trailingViews: [formatPopup]),
                SettingsRowView(
                    title: L10n.tr("image_upload.settings.encode_url"),
                    subtitle: L10n.tr("image_upload.encode_url_subtitle"),
                    trailingViews: [encodeURLSwitch]
                ),
                SettingsRowView(
                    title: L10n.tr("image_upload.settings.compress_quality"),
                    subtitle: L10n.tr("image_upload.compress_subtitle"),
                    trailingViews: [compressControl]
                ),
            ]
        )

        let hotkeysSection = SettingsSectionView(
            title: L10n.tr("image_upload.section.hotkeys"),
            rows: [
                SettingsRowView(title: L10n.tr("image_upload.settings.clipboard_hotkey"), trailingViews: [clipboardHotKeyRecorder]),
                SettingsRowView(title: L10n.tr("image_upload.settings.file_hotkey"), trailingViews: [fileHotKeyRecorder]),
            ]
        )

        preferencesContainer.orientation = .vertical
        preferencesContainer.alignment = .leading
        preferencesContainer.spacing = SettingsStyle.sectionSpacing
        preferencesContainer.translatesAutoresizingMaskIntoConstraints = false
        preferencesContainer.addArrangedSubview(generalSection)
        preferencesContainer.addArrangedSubview(hotkeysSection)
        NSLayoutConstraint.activate([
            generalSection.widthAnchor.constraint(equalTo: preferencesContainer.widthAnchor),
            hotkeysSection.widthAnchor.constraint(equalTo: preferencesContainer.widthAnchor),
        ])
    }

    private func configureHistoryTab() {
        clearHistoryButton.target = self
        clearHistoryButton.action = #selector(clearHistoryClicked)

        let headerBar = makeHeaderBar(title: L10n.tr("image_upload.section.history"), accessory: clearHistoryButton)
        historyContainer.orientation = .vertical
        historyContainer.alignment = .leading
        historyContainer.spacing = 8
        historyContainer.translatesAutoresizingMaskIntoConstraints = false
        historyContainer.addArrangedSubview(headerBar)
        historyContainer.addArrangedSubview(historyCard)
        NSLayoutConstraint.activate([
            headerBar.widthAnchor.constraint(equalTo: historyContainer.widthAnchor),
            historyCard.widthAnchor.constraint(equalTo: historyContainer.widthAnchor),
        ])
    }

    private func makeHeaderBar(title: String, accessory: NSView) -> NSView {
        let label = NSTextField(labelWithString: title)
        label.font = SettingsStyle.sectionTitleFont
        label.textColor = SettingsStyle.secondaryText
        label.translatesAutoresizingMaskIntoConstraints = false

        accessory.translatesAutoresizingMaskIntoConstraints = false
        let bar = NSView()
        bar.translatesAutoresizingMaskIntoConstraints = false
        bar.addSubview(label)
        bar.addSubview(accessory)
        NSLayoutConstraint.activate([
            bar.heightAnchor.constraint(greaterThanOrEqualToConstant: 24),
            label.leadingAnchor.constraint(equalTo: bar.leadingAnchor, constant: 4),
            label.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
            accessory.trailingAnchor.constraint(equalTo: bar.trailingAnchor),
            accessory.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
            accessory.topAnchor.constraint(greaterThanOrEqualTo: bar.topAnchor),
            accessory.bottomAnchor.constraint(lessThanOrEqualTo: bar.bottomAnchor),
        ])
        return bar
    }

    private func updateVisibleTab() {
        let selected = Tab(rawValue: tabControl.selectedSegment) ?? .hosts
        hostsContainer.isHidden = selected != .hosts
        preferencesContainer.isHidden = selected != .preferences
        historyContainer.isHidden = selected != .history
    }

    private func applyPreferencesUI(_ settings: ImageUploadSettings) {
        let formatIndex = UploadOutputFormat.allCases.firstIndex(of: settings.outputFormat) ?? 0
        formatPopup.selectItem(at: formatIndex)
        encodeURLSwitch.state = settings.encodeURL ? .on : .off
        compressSlider.integerValue = settings.compressFactor
        updateCompressBadge()
        clipboardHotKeyRecorder.setBinding(settings.uploadClipboardHotKey)
        fileHotKeyRecorder.setBinding(settings.uploadFileHotKey)
    }

    private func rebuildHostRows() {
        let hosts = appliedSettings.hosts
        if hosts.isEmpty {
            let empty = SettingsEmptyStateView(
                symbolName: "icloud.and.arrow.up",
                title: L10n.tr("image_upload.empty.hosts_title"),
                subtitle: L10n.tr("image_upload.empty.hosts_subtitle"),
                actionTitle: L10n.tr("image_upload.settings.add_host"),
                target: self,
                action: #selector(addHostClicked)
            )
            hostsCard.setRows([empty])
            return
        }

        let activeID = appliedSettings.selectedHostID ?? hosts.first?.id
        let rows = hosts.map { host -> NSView in
            let isDefault = host.id == activeID
            let hasSecret = ((try? secretStore.secret(for: host.id)) ?? nil)?.isEmpty == false

            let iconBadge = SettingsIconBadgeView(symbolName: "icloud.fill", accented: isDefault)

            var badges: [NSView] = [SettingsBadgeLabel(text: host.provider.title, tone: .neutral)]
            if isDefault {
                badges.insert(SettingsBadgeLabel(text: L10n.tr("image_upload.badge.default"), tone: .accent), at: 0)
            }

            let targetSummary = [host.bucket, host.domain].filter { !$0.isEmpty }.joined(separator: " · ")
            let secretSummary = hasSecret ? L10n.tr("image_upload.badge.keychain_saved") : ""
            let subtitle = [targetSummary, secretSummary].filter { !$0.isEmpty }.joined(separator: " · ")

            var trailing: [NSView] = []
            if !isDefault {
                let defaultButton = SettingsStyle.makeButton(
                    title: L10n.tr("image_upload.settings.set_default"),
                    primary: false,
                    target: self,
                    action: #selector(setDefaultHostClicked(_:))
                )
                defaultButton.controlSize = .small
                defaultButton.identifier = NSUserInterfaceItemIdentifier(host.id)
                defaultButton.setAccessibilityLabel(L10n.format("image_upload.row.set_default_accessibility", host.name))
                trailing.append(defaultButton)
            }

            let editButton = SettingsIconButton(
                symbolName: "pencil",
                accessibilityLabel: L10n.format("image_upload.row.edit_accessibility", host.name),
                tooltip: L10n.tr("common.edit"),
                target: self,
                action: #selector(editHostClicked(_:))
            )
            editButton.identifier = NSUserInterfaceItemIdentifier(host.id)

            let deleteButton = SettingsIconButton(
                symbolName: "trash",
                accessibilityLabel: L10n.format("image_upload.row.delete_accessibility", host.name),
                tooltip: L10n.tr("common.delete"),
                isDestructive: true,
                target: self,
                action: #selector(removeHostClicked(_:))
            )
            deleteButton.identifier = NSUserInterfaceItemIdentifier(host.id)

            trailing.append(contentsOf: [editButton, deleteButton])

            return SettingsRowView(
                title: host.name,
                subtitle: subtitle,
                leadingView: iconBadge,
                trailingViews: trailing,
                titleBadges: badges
            )
        }
        hostsCard.setRows(rows)
    }

    private func rebuildHistoryRows() {
        if historyItems.isEmpty {
            let empty = SettingsEmptyStateView(
                symbolName: "clock.arrow.circlepath",
                title: L10n.tr("image_upload.empty.history_title"),
                subtitle: L10n.tr("image_upload.empty.history_subtitle")
            )
            historyCard.setRows([empty])
            return
        }

        let rows = historyItems.map { item -> NSView in
            let thumbView = NSImageView()
            thumbView.wantsLayer = true
            thumbView.layer?.cornerRadius = 6
            thumbView.layer?.masksToBounds = true
            thumbView.translatesAutoresizingMaskIntoConstraints = false
            if let data = item.thumbnailData, let img = NSImage(data: data) {
                thumbView.image = img
                thumbView.imageScaling = .scaleProportionallyUpOrDown
            } else {
                let config = NSImage.SymbolConfiguration(pointSize: 15, weight: .medium)
                thumbView.image = NSImage(systemSymbolName: "photo", accessibilityDescription: nil)?
                    .withSymbolConfiguration(config)
                thumbView.contentTintColor = .secondaryLabelColor
            }
            NSLayoutConstraint.activate([
                thumbView.widthAnchor.constraint(equalToConstant: 32),
                thumbView.heightAnchor.constraint(equalToConstant: 32),
            ])

            let hostBadge = SettingsBadgeLabel(text: item.hostName, tone: .neutral)
            let copyButton = SettingsStyle.makeButton(
                title: L10n.tr("image_upload.history.copy"),
                symbolName: "doc.on.doc",
                primary: false,
                target: self,
                action: #selector(copyHistoryRowClicked(_:))
            )
            copyButton.controlSize = .small
            copyButton.identifier = NSUserInterfaceItemIdentifier(item.id)
            copyButton.setAccessibilityLabel(L10n.format("image_upload.row.copy_accessibility", item.filename))

            return SettingsRowView(
                title: item.filename,
                subtitle: item.url,
                leadingView: thumbView,
                trailingViews: [copyButton],
                titleBadges: [hostBadge]
            )
        }
        historyCard.setRows(rows)
    }

    private func presentHostSheet(editing host: ImageHostConfig?) {
        guard let window, activeSheet == nil else { return }
        let hasStoredSecret = host.flatMap { (try? secretStore.secret(for: $0.id)) ?? nil }?.isEmpty == false
        let defaultName = L10n.format("image_upload.default_host_name", appliedSettings.hosts.count + 1)

        let sheet = ImageHostEditorSheet(
            editing: host,
            defaultName: defaultName,
            hasStoredSecret: hasStoredSecret,
            onCommit: { [weak self] candidate, newSecret in
                guard let self else { return .success(()) }
                let updatedHosts: [ImageHostConfig]
                if let existing = host, let idx = self.appliedSettings.hosts.firstIndex(where: { $0.id == existing.id }) {
                    updatedHosts = self.appliedSettings.hosts.enumerated().map { $0.offset == idx ? candidate : $0.element }
                } else {
                    updatedHosts = self.appliedSettings.hosts + [candidate]
                }
                let nextSelectedID = self.appliedSettings.selectedHostID ?? candidate.id
                let next = ImageUploadSettings(
                    hosts: updatedHosts,
                    selectedHostID: nextSelectedID,
                    outputFormat: self.appliedSettings.outputFormat,
                    compressFactor: self.appliedSettings.compressFactor,
                    encodeURL: self.appliedSettings.encodeURL,
                    uploadClipboardHotKey: self.appliedSettings.uploadClipboardHotKey,
                    uploadFileHotKey: self.appliedSettings.uploadFileHotKey
                )
                let afterApply: (() throws -> Void)? = newSecret.map { secret in
                    { [secretStore = self.secretStore, hostID = candidate.id] in
                        try secretStore.setSecret(secret, for: hostID)
                    }
                }
                let result = self.onCommitSettings?(next, afterApply) ?? .success(())
                if case .success = result {
                    self.appliedSettings = next
                    self.rebuildHostRows()
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

    private func snappedCompressFactor() -> Int {
        let raw = compressSlider.integerValue
        let snapped = Int((Double(raw) / 5.0).rounded()) * 5
        return min(max(snapped, 10), 100)
    }

    private func updateCompressBadge() {
        let value = snappedCompressFactor()
        let text = value >= 100 ? L10n.tr("image_upload.settings.compress_off") : "\(value)%"
        compressValueBadge.update(text: text)
    }

    private func commitPreferencesChange() {
        let formatIndex = max(0, min(UploadOutputFormat.allCases.count - 1, formatPopup.indexOfSelectedItem))
        let next = ImageUploadSettings(
            hosts: appliedSettings.hosts,
            selectedHostID: appliedSettings.selectedHostID,
            outputFormat: UploadOutputFormat.allCases[formatIndex],
            compressFactor: snappedCompressFactor(),
            encodeURL: encodeURLSwitch.state == .on,
            uploadClipboardHotKey: clipboardHotKeyRecorder.binding,
            uploadFileHotKey: fileHotKeyRecorder.binding
        )
        let result = onCommitSettings?(next, nil) ?? .success(())
        switch result {
        case .success:
            appliedSettings = next
        case .failure:
            applyPreferencesUI(appliedSettings)
        }
    }

    // MARK: - Actions

    @objc private func tabChanged() {
        updateVisibleTab()
    }

    @objc private func addHostClicked() {
        presentHostSheet(editing: nil)
    }

    @objc private func editHostClicked(_ sender: NSButton) {
        guard let id = sender.identifier?.rawValue,
              let host = appliedSettings.hosts.first(where: { $0.id == id }) else { return }
        presentHostSheet(editing: host)
    }

    @objc private func removeHostClicked(_ sender: NSButton) {
        guard let id = sender.identifier?.rawValue else { return }
        let updatedHosts = appliedSettings.hosts.filter { $0.id != id }
        let nextSelected = appliedSettings.selectedHostID == id ? updatedHosts.first?.id : appliedSettings.selectedHostID
        let next = ImageUploadSettings(
            hosts: updatedHosts,
            selectedHostID: nextSelected,
            outputFormat: appliedSettings.outputFormat,
            compressFactor: appliedSettings.compressFactor,
            encodeURL: appliedSettings.encodeURL,
            uploadClipboardHotKey: appliedSettings.uploadClipboardHotKey,
            uploadFileHotKey: appliedSettings.uploadFileHotKey
        )
        let result = onCommitSettings?(next) { [secretStore] in
            try secretStore.deleteSecret(for: id)
        } ?? .success(())
        if case .success = result {
            appliedSettings = next
            rebuildHostRows()
        }
    }

    @objc private func setDefaultHostClicked(_ sender: NSButton) {
        guard let id = sender.identifier?.rawValue,
              appliedSettings.hosts.contains(where: { $0.id == id }) else { return }
        let next = appliedSettings.withSelectedHostID(id)
        let result = onCommitSettings?(next, nil) ?? .success(())
        if case .success = result {
            appliedSettings = next
            rebuildHostRows()
        }
    }

    @objc private func preferencesControlChanged() {
        commitPreferencesChange()
    }

    @objc private func compressSliderChanged() {
        compressSlider.integerValue = snappedCompressFactor()
        updateCompressBadge()
        commitPreferencesChange()
    }

    @objc private func copyHistoryRowClicked(_ sender: NSButton) {
        guard let id = sender.identifier?.rawValue,
              let item = historyItems.first(where: { $0.id == id }) else { return }
        onCopyHistoryItem?(item)
    }

    @objc private func clearHistoryClicked() {
        onClearHistory?()
    }
}
