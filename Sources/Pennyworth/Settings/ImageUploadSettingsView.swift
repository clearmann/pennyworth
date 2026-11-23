import AppKit

@MainActor final class ImageUploadSettingsView: NSView {
    private let formatPopup = NSPopUpButton()
    private let encodeURLCheckbox = NSButton(checkboxWithTitle: L10n.tr("image_upload.settings.encode_url"), target: nil, action: nil)
    private let compressSlider = NSSlider(value: 100, minValue: 10, maxValue: 100, target: nil, action: nil)
    private let compressValueLabel = NSTextField(labelWithString: "")
    private let clipboardHotKeyRecorder = HotKeyRecorderView(binding: nil)
    private let fileHotKeyRecorder = HotKeyRecorderView(binding: nil)

    private let hostTableView = NSTableView()
    private let addHostButton = NSButton(title: L10n.tr("image_upload.settings.add_host"), target: nil, action: nil)
    private let removeHostButton = NSButton(title: L10n.tr("image_upload.settings.remove_host"), target: nil, action: nil)
    private let setDefaultButton = NSButton(title: L10n.tr("image_upload.settings.set_default"), target: nil, action: nil)

    private let providerPopup = NSPopUpButton()
    private let nameField = NSTextField()
    private let bucketField = NSTextField()
    private let regionLabel = NSTextField(labelWithString: L10n.tr("image_upload.field.region"))
    private let regionField = NSTextField()
    private let qiniuRegionPopup = NSPopUpButton()
    private let endpointRow = NSStackView()
    private let endpointLabel = NSTextField(labelWithString: L10n.tr("image_upload.field.endpoint"))
    private let endpointField = NSTextField()
    private let pathStyleCheckbox = NSButton(checkboxWithTitle: L10n.tr("image_upload.field.path_style"), target: nil, action: nil)
    private let accessKeyLabel = NSTextField(labelWithString: L10n.tr("image_upload.field.access_key"))
    private let accessKeyField = NSTextField()
    private let secretKeyLabel = NSTextField(labelWithString: L10n.tr("image_upload.field.secret_key"))
    private let secretKeyField = NSSecureTextField()
    private let domainLabel = NSTextField(labelWithString: L10n.tr("image_upload.field.domain"))
    private let domainField = NSTextField()
    private let saveKeyPathField = NSTextField()
    private let suffixField = NSTextField()

    private let historyTableView = NSTableView()
    private let copyHistoryButton = NSButton(title: L10n.tr("image_upload.history.copy"), target: nil, action: nil)
    private let clearHistoryButton = NSButton(title: L10n.tr("image_upload.history.clear"), target: nil, action: nil)

    private let secretStore: ImageUploadSecretStoring
    private(set) var hosts: [ImageHostConfig] = []
    private(set) var selectedHostID: String?
    private var pendingSecrets: [String: String] = [:]
    private var removedHostIDs = Set<String>()
    private var historyItems: [UploadHistoryItem] = []

    var onRecordingStateChanged: ((Bool) -> Void)? {
        didSet {
            clipboardHotKeyRecorder.onRecordingStateChanged = onRecordingStateChanged
            fileHotKeyRecorder.onRecordingStateChanged = onRecordingStateChanged
        }
    }
    var onCopyHistoryItem: ((UploadHistoryItem) -> Void)?
    var onClearHistory: (() -> Void)?

    init(secretStore: ImageUploadSecretStoring = KeychainSecretStore()) {
        self.secretStore = secretStore
        super.init(frame: .zero)
        configure()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func reload(_ settings: ImageUploadSettings, history: [UploadHistoryItem]) {
        hosts = settings.hosts
        selectedHostID = settings.selectedHostID ?? settings.hosts.first?.id
        pendingSecrets = [:]
        removedHostIDs = []

        let formatIndex = UploadOutputFormat.allCases.firstIndex(of: settings.outputFormat) ?? 0
        formatPopup.selectItem(at: formatIndex)
        encodeURLCheckbox.state = settings.encodeURL ? .on : .off
        compressSlider.integerValue = settings.compressFactor
        updateCompressLabel()
        clipboardHotKeyRecorder.setBinding(settings.uploadClipboardHotKey)
        fileHotKeyRecorder.setBinding(settings.uploadFileHotKey)

        hostTableView.reloadData()
        if let active = selectedHostID, let idx = hosts.firstIndex(where: { $0.id == active }) {
            selectHostRow(idx)
        } else {
            selectHostRow(hosts.isEmpty ? -1 : 0)
        }

        reloadHistory(history)
    }

    func reloadHistory(_ items: [UploadHistoryItem]) {
        historyItems = items
        historyTableView.reloadData()
        updateHistoryButtons()
    }

    func buildValidatedSettings() throws -> ImageUploadSettings {
        let formatIndex = max(0, min(UploadOutputFormat.allCases.count - 1, formatPopup.indexOfSelectedItem))
        let normalizedHosts = hosts.map(\.trimmed)
        let normalizedDefault: String?
        if let selectedHostID, normalizedHosts.contains(where: { $0.id == selectedHostID }) {
            normalizedDefault = selectedHostID
        } else {
            normalizedDefault = normalizedHosts.first?.id
        }

        let settings = ImageUploadSettings(
            hosts: normalizedHosts,
            selectedHostID: normalizedDefault,
            outputFormat: UploadOutputFormat.allCases[formatIndex],
            compressFactor: snappedCompressFactor(),
            encodeURL: encodeURLCheckbox.state == .on,
            uploadClipboardHotKey: clipboardHotKeyRecorder.binding,
            uploadFileHotKey: fileHotKeyRecorder.binding
        )
        try ImageUploadSettings.validate(settings)

        for host in normalizedHosts {
            let pending = pendingSecrets[host.id]?.trimmingCharacters(in: .whitespacesAndNewlines)
            let existing = try secretStore.secret(for: host.id)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let effectiveSecret = (pending?.isEmpty == false) ? pending : existing
            guard let effectiveSecret, !effectiveSecret.isEmpty else {
                throw ImageUploadError.missingSecretKey(hostName: host.name)
            }
        }
        return settings
    }

    func commitPendingSecrets() throws {
        for hostID in removedHostIDs {
            try secretStore.deleteSecret(for: hostID)
        }
        for (hostID, secret) in pendingSecrets {
            let trimmed = secret.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                try secretStore.setSecret(trimmed, for: hostID)
            }
        }
        removedHostIDs.removeAll()
        pendingSecrets.removeAll()
        updateHostEditor()
    }

    // MARK: - Layout

    private func configure() {
        translatesAutoresizingMaskIntoConstraints = false
        configureGeneralControls()
        configureHostTable()
        configureHostEditor()
        configureHistoryTable()

        let generalSection = makeSectionHeader(L10n.tr("image_upload.section.general"))
        let hostsSection = makeSectionHeader(L10n.tr("image_upload.section.hosts"))
        let historySection = makeSectionHeader(L10n.tr("image_upload.section.history"))

        let compressControl = NSStackView(views: [compressSlider, compressValueLabel])
        compressControl.alignment = .centerY
        compressControl.spacing = 10

        let hostButtons = NSStackView(views: [addHostButton, removeHostButton, setDefaultButton])
        hostButtons.spacing = 10

        let historyButtons = NSStackView(views: [copyHistoryButton, clearHistoryButton])
        historyButtons.spacing = 10

        let hostScroll = hostTableView.enclosingScrollView!
        let historyScroll = historyTableView.enclosingScrollView!
        let editor = buildEditorStack()

        let templateNote = NSTextField(wrappingLabelWithString: L10n.tr("image_upload.settings.template_note"))
        templateNote.font = .systemFont(ofSize: 11)
        templateNote.textColor = .secondaryLabelColor

        let stack = NSStackView(views: [
            generalSection,
            row(L10n.tr("image_upload.settings.output_format"), formatPopup),
            encodeURLCheckbox,
            row(L10n.tr("image_upload.settings.compress_quality"), compressControl),
            row(L10n.tr("image_upload.settings.clipboard_hotkey"), clipboardHotKeyRecorder),
            row(L10n.tr("image_upload.settings.file_hotkey"), fileHotKeyRecorder),
            separator(),
            hostsSection,
            hostScroll,
            hostButtons,
            editor,
            templateNote,
            separator(),
            historySection,
            historyScroll,
            historyButtons,
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            hostScroll.widthAnchor.constraint(equalTo: stack.widthAnchor),
            hostScroll.heightAnchor.constraint(equalToConstant: 120),
            editor.widthAnchor.constraint(equalTo: stack.widthAnchor),
            templateNote.widthAnchor.constraint(lessThanOrEqualTo: stack.widthAnchor),
            historyScroll.widthAnchor.constraint(equalTo: stack.widthAnchor),
            historyScroll.heightAnchor.constraint(equalToConstant: 120),
        ])

        updateCompressLabel()
        updateHostEditor()
        updateHistoryButtons()
    }

    private func configureGeneralControls() {
        formatPopup.addItems(withTitles: UploadOutputFormat.allCases.map(\.title))
        formatPopup.setAccessibilityLabel(L10n.tr("image_upload.settings.output_format"))
        formatPopup.widthAnchor.constraint(equalToConstant: 180).isActive = true

        encodeURLCheckbox.setAccessibilityLabel(L10n.tr("image_upload.settings.encode_url"))

        compressSlider.numberOfTickMarks = 19
        compressSlider.allowsTickMarkValuesOnly = true
        compressSlider.isContinuous = true
        compressSlider.target = self
        compressSlider.action = #selector(compressSliderChanged)
        compressSlider.setAccessibilityLabel(L10n.tr("image_upload.settings.compress_quality"))
        compressSlider.widthAnchor.constraint(equalToConstant: 220).isActive = true

        compressValueLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        compressValueLabel.textColor = .secondaryLabelColor

        clipboardHotKeyRecorder.setAccessibilityLabel(L10n.tr("image_upload.settings.clipboard_hotkey"))
        fileHotKeyRecorder.setAccessibilityLabel(L10n.tr("image_upload.settings.file_hotkey"))
    }

    private func configureHostTable() {
        for (id, key, width) in [
            ("default", "image_upload.column.default", 44.0),
            ("name", "image_upload.column.name", 130.0),
            ("provider", "image_upload.column.provider", 110.0),
            ("bucket", "image_upload.column.bucket", 180.0),
        ] {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id))
            column.title = L10n.tr(key)
            column.width = width
            hostTableView.addTableColumn(column)
        }
        hostTableView.dataSource = self
        hostTableView.delegate = self
        hostTableView.rowHeight = 24
        hostTableView.allowsMultipleSelection = false
        hostTableView.setAccessibilityLabel(L10n.tr("image_upload.settings.hosts_list"))

        let scroll = NSScrollView()
        scroll.documentView = hostTableView
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        scroll.translatesAutoresizingMaskIntoConstraints = false

        addHostButton.target = self
        addHostButton.action = #selector(addHostClicked)
        removeHostButton.target = self
        removeHostButton.action = #selector(removeHostClicked)
        setDefaultButton.target = self
        setDefaultButton.action = #selector(setDefaultClicked)
    }

    private func configureHostEditor() {
        providerPopup.addItems(withTitles: ImageHostProvider.allCases.map(\.title))
        providerPopup.target = self
        providerPopup.action = #selector(providerChanged)
        providerPopup.setAccessibilityLabel(L10n.tr("image_upload.field.provider"))
        providerPopup.widthAnchor.constraint(equalToConstant: 200).isActive = true

        qiniuRegionPopup.addItems(withTitles: QiniuRegion.allCases.map(\.title))
        qiniuRegionPopup.target = self
        qiniuRegionPopup.action = #selector(qiniuRegionChanged)
        qiniuRegionPopup.setAccessibilityLabel(L10n.tr("image_upload.field.region"))
        qiniuRegionPopup.widthAnchor.constraint(equalToConstant: 200).isActive = true

        pathStyleCheckbox.target = self
        pathStyleCheckbox.action = #selector(pathStyleChanged)

        let textFields: [(NSTextField, String)] = [
            (nameField, "image_upload.field.name"),
            (bucketField, "image_upload.field.bucket"),
            (regionField, "image_upload.field.region"),
            (endpointField, "image_upload.field.endpoint"),
            (accessKeyField, "image_upload.field.access_key"),
            (secretKeyField, "image_upload.field.secret_key"),
            (domainField, "image_upload.field.domain"),
            (saveKeyPathField, "image_upload.field.save_key_path"),
            (suffixField, "image_upload.field.suffix"),
        ]
        for (field, key) in textFields {
            field.delegate = self
            field.setAccessibilityLabel(L10n.tr(key))
            field.lineBreakMode = .byTruncatingMiddle
        }

        nameField.placeholderString = L10n.tr("image_upload.placeholder.name")
        bucketField.placeholderString = L10n.tr("image_upload.placeholder.bucket")
        saveKeyPathField.placeholderString = ImageHostConfig.defaultSaveKeyPath
        suffixField.placeholderString = L10n.tr("image_upload.placeholder.suffix")
    }

    private func buildEditorStack() -> NSStackView {
        let regionControl = NSStackView(views: [regionField, qiniuRegionPopup])
        regionControl.spacing = 8

        endpointLabel.widthAnchor.constraint(equalToConstant: 120).isActive = true
        endpointRow.orientation = .horizontal
        endpointRow.alignment = .centerY
        endpointRow.spacing = 10
        endpointRow.addArrangedSubview(endpointLabel)
        endpointRow.addArrangedSubview(endpointField)

        let rows: [NSView] = [
            row(L10n.tr("image_upload.field.provider"), providerPopup),
            row(L10n.tr("image_upload.field.name"), nameField),
            row(L10n.tr("image_upload.field.bucket"), bucketField),
            customLabelRow(regionLabel, regionControl),
            endpointRow,
            pathStyleCheckbox,
            customLabelRow(accessKeyLabel, accessKeyField),
            customLabelRow(secretKeyLabel, secretKeyField),
            customLabelRow(domainLabel, domainField),
            row(L10n.tr("image_upload.field.save_key_path"), saveKeyPathField),
            row(L10n.tr("image_upload.field.suffix"), suffixField),
        ]

        let stack = NSStackView(views: rows)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false

        let fullWidthFields: [NSView] = [
            nameField, bucketField, regionField, endpointField,
            accessKeyField, secretKeyField, domainField, saveKeyPathField, suffixField,
        ]
        for field in fullWidthFields {
            field.widthAnchor.constraint(greaterThanOrEqualToConstant: 260).isActive = true
            field.widthAnchor.constraint(lessThanOrEqualTo: stack.widthAnchor, constant: -130).isActive = true
        }
        return stack
    }

    private func configureHistoryTable() {
        for (id, key, width) in [
            ("filename", "image_upload.history.column.file", 140.0),
            ("host", "image_upload.history.column.host", 100.0),
            ("url", "image_upload.history.column.url", 260.0),
        ] {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id))
            column.title = L10n.tr(key)
            column.width = width
            historyTableView.addTableColumn(column)
        }
        historyTableView.dataSource = self
        historyTableView.delegate = self
        historyTableView.rowHeight = 24
        historyTableView.allowsMultipleSelection = false
        historyTableView.setAccessibilityLabel(L10n.tr("image_upload.history.list_accessibility"))

        let scroll = NSScrollView()
        scroll.documentView = historyTableView
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        scroll.translatesAutoresizingMaskIntoConstraints = false

        copyHistoryButton.target = self
        copyHistoryButton.action = #selector(copyHistoryClicked)
        clearHistoryButton.target = self
        clearHistoryButton.action = #selector(clearHistoryClicked)
    }

    private func makeSectionHeader(_ title: String) -> NSTextField {
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 13, weight: .semibold)
        return label
    }

    private func separator() -> NSBox {
        let box = NSBox()
        box.boxType = .separator
        box.translatesAutoresizingMaskIntoConstraints = false
        return box
    }

    private func row(_ title: String, _ control: NSView) -> NSStackView {
        let label = NSTextField(labelWithString: title)
        return customLabelRow(label, control)
    }

    private func customLabelRow(_ label: NSTextField, _ control: NSView) -> NSStackView {
        label.widthAnchor.constraint(equalToConstant: 120).isActive = true
        let stack = NSStackView(views: [label, control])
        stack.alignment = .centerY
        stack.spacing = 10
        return stack
    }

    // MARK: - State updates

    private func snappedCompressFactor() -> Int {
        let raw = compressSlider.integerValue
        let snapped = Int((Double(raw) / 5.0).rounded()) * 5
        return max(10, min(100, snapped))
    }

    private func updateCompressLabel() {
        let factor = snappedCompressFactor()
        if factor >= 100 {
            compressValueLabel.stringValue = L10n.tr("image_upload.settings.compress_off")
        } else {
            compressValueLabel.stringValue = "\(factor)%"
        }
    }

    private func selectHostRow(_ index: Int) {
        if hosts.indices.contains(index) {
            hostTableView.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
            hostTableView.scrollRowToVisible(index)
        } else {
            hostTableView.deselectAll(nil)
        }
        updateHostEditor()
    }

    private func updateHostEditor() {
        let index = hostTableView.selectedRow
        let hasSelection = hosts.indices.contains(index)
        removeHostButton.isEnabled = hasSelection
        setDefaultButton.isEnabled = hasSelection

        let editableFields: [NSTextField] = [
            nameField, bucketField, regionField, endpointField,
            accessKeyField, secretKeyField, domainField, saveKeyPathField, suffixField,
        ]
        providerPopup.isEnabled = hasSelection
        qiniuRegionPopup.isEnabled = hasSelection
        pathStyleCheckbox.isEnabled = hasSelection

        guard hasSelection else {
            for field in editableFields {
                field.stringValue = ""
                field.isEnabled = false
            }
            regionField.isHidden = false
            qiniuRegionPopup.isHidden = true
            endpointRow.isHidden = false
            pathStyleCheckbox.isHidden = false
            return
        }

        let host = hosts[index]
        for field in editableFields { field.isEnabled = true }

        let providerIndex = ImageHostProvider.allCases.firstIndex(of: host.provider) ?? 0
        providerPopup.selectItem(at: providerIndex)
        nameField.stringValue = host.name
        bucketField.stringValue = host.bucket
        regionField.stringValue = host.region
        endpointField.stringValue = host.endpoint
        pathStyleCheckbox.state = host.usePathStyle ? .on : .off
        accessKeyField.stringValue = host.accessKey
        domainField.stringValue = host.domain
        saveKeyPathField.stringValue = host.saveKeyPath
        suffixField.stringValue = host.suffix

        let hasStoredSecret = ((try? secretStore.secret(for: host.id)) ?? nil)?.isEmpty == false
        if let pending = pendingSecrets[host.id] {
            secretKeyField.stringValue = pending
            secretKeyField.placeholderString = L10n.tr("image_upload.placeholder.secret_key")
        } else {
            secretKeyField.stringValue = ""
            secretKeyField.placeholderString = hasStoredSecret
                ? L10n.tr("image_upload.placeholder.secret_key_saved")
                : L10n.tr("image_upload.placeholder.secret_key")
        }

        applyProviderFieldVisibility(host)
    }

    private func applyProviderFieldVisibility(_ host: ImageHostConfig) {
        switch host.provider {
        case .s3:
            regionLabel.stringValue = L10n.tr("image_upload.field.region")
            regionField.isHidden = false
            qiniuRegionPopup.isHidden = true
            regionField.placeholderString = "auto / us-east-1"
            endpointRow.isHidden = false
            endpointField.placeholderString = "https://<account>.r2.cloudflarestorage.com"
            pathStyleCheckbox.isHidden = false
            accessKeyLabel.stringValue = L10n.tr("image_upload.field.access_key")
            secretKeyLabel.stringValue = L10n.tr("image_upload.field.secret_key")
            domainLabel.stringValue = L10n.tr("image_upload.field.domain")
            domainField.placeholderString = L10n.tr("image_upload.placeholder.domain_optional")
        case .aliyunOSS:
            regionLabel.stringValue = L10n.tr("image_upload.field.region")
            regionField.isHidden = false
            qiniuRegionPopup.isHidden = true
            regionField.placeholderString = "oss-cn-hangzhou"
            endpointRow.isHidden = false
            endpointField.placeholderString = L10n.tr("image_upload.placeholder.endpoint_optional")
            pathStyleCheckbox.isHidden = true
            accessKeyLabel.stringValue = "AccessKey ID"
            secretKeyLabel.stringValue = "AccessKey Secret"
            domainLabel.stringValue = L10n.tr("image_upload.field.domain")
            domainField.placeholderString = L10n.tr("image_upload.placeholder.domain_optional")
        case .tencentCOS:
            regionLabel.stringValue = L10n.tr("image_upload.field.region")
            regionField.isHidden = false
            qiniuRegionPopup.isHidden = true
            regionField.placeholderString = "ap-guangzhou"
            endpointRow.isHidden = false
            endpointField.placeholderString = L10n.tr("image_upload.placeholder.endpoint_optional")
            pathStyleCheckbox.isHidden = true
            accessKeyLabel.stringValue = "SecretId"
            secretKeyLabel.stringValue = "SecretKey"
            domainLabel.stringValue = L10n.tr("image_upload.field.domain")
            domainField.placeholderString = L10n.tr("image_upload.placeholder.domain_optional")
        case .qiniu:
            regionLabel.stringValue = L10n.tr("image_upload.field.region")
            regionField.isHidden = true
            qiniuRegionPopup.isHidden = false
            let qiniuRegion = QiniuRegion(rawValue: host.region) ?? .z0
            let qIndex = QiniuRegion.allCases.firstIndex(of: qiniuRegion) ?? 0
            qiniuRegionPopup.selectItem(at: qIndex)
            endpointRow.isHidden = qiniuRegion != .custom
            endpointField.placeholderString = "https://upload.qiniup.com"
            pathStyleCheckbox.isHidden = true
            accessKeyLabel.stringValue = "AccessKey"
            secretKeyLabel.stringValue = "SecretKey"
            domainLabel.stringValue = L10n.tr("image_upload.field.domain_required")
            domainField.placeholderString = "https://cdn.example.com"
        }
    }

    private func replaceSelectedHost(with updated: ImageHostConfig) {
        let index = hostTableView.selectedRow
        guard hosts.indices.contains(index) else { return }
        hosts = hosts.enumerated().map { $0.offset == index ? updated : $0.element }
        hostTableView.reloadData(
            forRowIndexes: IndexSet(integer: index),
            columnIndexes: IndexSet(integersIn: 0..<hostTableView.numberOfColumns)
        )
    }

    private func updateHistoryButtons() {
        copyHistoryButton.isEnabled = historyItems.indices.contains(historyTableView.selectedRow)
        clearHistoryButton.isEnabled = !historyItems.isEmpty
    }

    // MARK: - Actions

    @objc private func compressSliderChanged() {
        compressSlider.integerValue = snappedCompressFactor()
        updateCompressLabel()
    }

    @objc private func addHostClicked() {
        let nextIndex = hosts.count + 1
        let name = L10n.format("image_upload.default_host_name", nextIndex)
        let created = ImageHostConfig.makeTemplate(for: .s3, name: name)
        hosts = hosts + [created]
        if selectedHostID == nil {
            selectedHostID = created.id
        }
        hostTableView.reloadData()
        selectHostRow(hosts.count - 1)
        window?.makeFirstResponder(nameField)
    }

    @objc private func removeHostClicked() {
        let index = hostTableView.selectedRow
        guard hosts.indices.contains(index) else { return }
        let removed = hosts[index]
        removedHostIDs.insert(removed.id)
        pendingSecrets.removeValue(forKey: removed.id)
        hosts = hosts.enumerated().filter { $0.offset != index }.map(\.element)
        if selectedHostID == removed.id {
            selectedHostID = hosts.first?.id
        }
        hostTableView.reloadData()
        selectHostRow(min(index, hosts.count - 1))
    }

    @objc private func setDefaultClicked() {
        let index = hostTableView.selectedRow
        guard hosts.indices.contains(index) else { return }
        selectedHostID = hosts[index].id
        hostTableView.reloadData()
        hostTableView.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
    }

    @objc private func providerChanged() {
        let index = hostTableView.selectedRow
        guard hosts.indices.contains(index) else { return }
        let current = hosts[index]
        let pIndex = max(0, min(ImageHostProvider.allCases.count - 1, providerPopup.indexOfSelectedItem))
        let nextProvider = ImageHostProvider.allCases[pIndex]
        guard nextProvider != current.provider else { return }

        let template = ImageHostConfig.makeTemplate(for: nextProvider, name: current.name)
        let updated = ImageHostConfig(
            id: current.id,
            name: current.name,
            provider: nextProvider,
            bucket: current.bucket,
            region: template.region,
            endpoint: nextProvider == .qiniu ? "" : current.endpoint,
            accessKey: current.accessKey,
            domain: current.domain,
            saveKeyPath: current.saveKeyPath,
            suffix: current.suffix,
            usePathStyle: template.usePathStyle
        )
        replaceSelectedHost(with: updated)
        updateHostEditor()
    }

    @objc private func qiniuRegionChanged() {
        let index = hostTableView.selectedRow
        guard hosts.indices.contains(index) else { return }
        let current = hosts[index]
        let rIndex = max(0, min(QiniuRegion.allCases.count - 1, qiniuRegionPopup.indexOfSelectedItem))
        let region = QiniuRegion.allCases[rIndex]
        let updated = ImageHostConfig(
            id: current.id,
            name: current.name,
            provider: current.provider,
            bucket: current.bucket,
            region: region.rawValue,
            endpoint: region == .custom ? current.endpoint : "",
            accessKey: current.accessKey,
            domain: current.domain,
            saveKeyPath: current.saveKeyPath,
            suffix: current.suffix,
            usePathStyle: current.usePathStyle
        )
        replaceSelectedHost(with: updated)
        applyProviderFieldVisibility(updated)
    }

    @objc private func pathStyleChanged() {
        let index = hostTableView.selectedRow
        guard hosts.indices.contains(index) else { return }
        let current = hosts[index]
        let updated = ImageHostConfig(
            id: current.id,
            name: current.name,
            provider: current.provider,
            bucket: current.bucket,
            region: current.region,
            endpoint: current.endpoint,
            accessKey: current.accessKey,
            domain: current.domain,
            saveKeyPath: current.saveKeyPath,
            suffix: current.suffix,
            usePathStyle: pathStyleCheckbox.state == .on
        )
        replaceSelectedHost(with: updated)
    }

    @objc private func copyHistoryClicked() {
        let index = historyTableView.selectedRow
        guard historyItems.indices.contains(index) else { return }
        onCopyHistoryItem?(historyItems[index])
    }

    @objc private func clearHistoryClicked() {
        onClearHistory?()
    }
}

extension ImageUploadSettingsView: NSTableViewDataSource, NSTableViewDelegate {
    func numberOfRows(in tableView: NSTableView) -> Int {
        tableView === hostTableView ? hosts.count : historyItems.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let columnID = tableColumn?.identifier.rawValue ?? ""
        let text: String
        if tableView === hostTableView {
            let host = hosts[row]
            switch columnID {
            case "default": text = host.id == selectedHostID ? "★" : ""
            case "name": text = host.name
            case "provider": text = host.provider.title
            case "bucket": text = host.bucket.isEmpty ? host.domain : host.bucket
            default: text = ""
            }
        } else {
            let item = historyItems[row]
            switch columnID {
            case "filename": text = item.filename
            case "host": text = item.hostName
            case "url": text = item.url
            default: text = ""
            }
        }

        let cellID = NSUserInterfaceItemIdentifier("ImageUploadCell.\(columnID)")
        let cell = (tableView.makeView(withIdentifier: cellID, owner: self) as? NSTextField)
            ?? NSTextField(labelWithString: "")
        cell.identifier = cellID
        cell.stringValue = text
        cell.lineBreakMode = .byTruncatingMiddle
        cell.font = .systemFont(ofSize: 12)
        if tableView === hostTableView && columnID == "default" {
            cell.alignment = .center
        }
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        if (notification.object as? NSTableView) === hostTableView {
            updateHostEditor()
        } else if (notification.object as? NSTableView) === historyTableView {
            updateHistoryButtons()
        }
    }
}

extension ImageUploadSettingsView: NSTextFieldDelegate {
    func controlTextDidChange(_ obj: Notification) {
        let index = hostTableView.selectedRow
        guard hosts.indices.contains(index) else { return }
        let current = hosts[index]

        if (obj.object as? NSTextField) === secretKeyField {
            pendingSecrets[current.id] = secretKeyField.stringValue
            return
        }

        let updated = ImageHostConfig(
            id: current.id,
            name: nameField.stringValue,
            provider: current.provider,
            bucket: bucketField.stringValue,
            region: current.provider == .qiniu ? current.region : regionField.stringValue,
            endpoint: endpointField.stringValue,
            accessKey: accessKeyField.stringValue,
            domain: domainField.stringValue,
            saveKeyPath: saveKeyPathField.stringValue,
            suffix: suffixField.stringValue,
            usePathStyle: current.usePathStyle
        )
        replaceSelectedHost(with: updated)
    }
}
