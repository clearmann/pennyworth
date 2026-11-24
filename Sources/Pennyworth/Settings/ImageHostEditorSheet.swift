import AppKit

/// Modal sheet for adding or editing a cloud image host configuration with Keychain secret handling.
@MainActor final class ImageHostEditorSheet: NSObject {
    let sheetWindow: NSWindow

    private let providerPopup = NSPopUpButton()
    private let nameField = NSTextField()
    private let bucketField = NSTextField()
    private let regionLabel = NSTextField(labelWithString: L10n.tr("image_upload.field.region"))
    private let regionField = NSTextField()
    private let qiniuRegionPopup = NSPopUpButton()
    private let endpointLabel = NSTextField(labelWithString: L10n.tr("image_upload.field.endpoint"))
    private let endpointField = NSTextField()
    private let pathStyleSwitch = NSSwitch()
    private let accessKeyLabel = NSTextField(labelWithString: L10n.tr("image_upload.field.access_key"))
    private let accessKeyField = NSTextField()
    private let secretKeyLabel = NSTextField(labelWithString: L10n.tr("image_upload.field.secret_key"))
    private let secretKeyField = NSSecureTextField()
    private let domainLabel = NSTextField(labelWithString: L10n.tr("image_upload.field.domain"))
    private let domainField = NSTextField()
    private let saveKeyPathField = NSTextField()
    private let suffixField = NSTextField()

    private let authCard = SettingsCardView()
    private var regionRowView: NSView!
    private var endpointRowView: NSView!
    private var pathStyleRowView: NSView!
    private var bucketRowView: NSView!
    private var accessKeyRowView: NSView!
    private var secretKeyRowView: NSView!

    private let errorBanner = SettingsStatusBanner()
    private let cancelButton: NSButton
    private let saveButton: NSButton

    private let editingHost: ImageHostConfig?
    private let hasStoredSecret: Bool
    private var currentProvider: ImageHostProvider
    private weak var parentWindow: NSWindow?
    private let onCommit: (ImageHostConfig, String?) -> Result<Void, Error>
    private let onDismiss: () -> Void

    init(
        editing: ImageHostConfig?,
        defaultName: String,
        hasStoredSecret: Bool,
        onCommit: @escaping (ImageHostConfig, String?) -> Result<Void, Error>,
        onDismiss: @escaping () -> Void
    ) {
        self.editingHost = editing
        self.hasStoredSecret = hasStoredSecret
        self.currentProvider = editing?.provider ?? .s3
        self.onCommit = onCommit
        self.onDismiss = onDismiss
        self.sheetWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 610),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        self.cancelButton = SettingsStyle.makeButton(
            title: L10n.tr("common.cancel"),
            primary: false,
            target: nil,
            action: nil
        )
        self.saveButton = SettingsStyle.makeButton(
            title: L10n.tr("settings.save"),
            primary: true,
            target: nil,
            action: nil
        )
        super.init()
        configureControls(initial: editing ?? ImageHostConfig.makeTemplate(for: .s3, name: defaultName))
        configureLayout()
        applyProviderAppearance(resettingProviderDefaults: false)
    }

    func present(on window: NSWindow) {
        parentWindow = window
        window.beginSheet(sheetWindow) { [weak self] _ in
            self?.sheetWindow.makeFirstResponder(nil)
            self?.onDismiss()
        }
        sheetWindow.makeFirstResponder(nameField)
    }

    private func configureControls(initial host: ImageHostConfig) {
        providerPopup.addItems(withTitles: ImageHostProvider.allCases.map(\.title))
        providerPopup.selectItem(at: ImageHostProvider.allCases.firstIndex(of: host.provider) ?? 0)
        providerPopup.target = self
        providerPopup.action = #selector(providerChanged)
        providerPopup.setAccessibilityLabel(L10n.tr("image_upload.field.provider"))
        providerPopup.widthAnchor.constraint(equalToConstant: 200).isActive = true

        qiniuRegionPopup.addItems(withTitles: QiniuRegion.allCases.map(\.title))
        let qRegion = QiniuRegion(rawValue: host.region) ?? .z0
        qiniuRegionPopup.selectItem(at: QiniuRegion.allCases.firstIndex(of: qRegion) ?? 0)
        qiniuRegionPopup.target = self
        qiniuRegionPopup.action = #selector(qiniuRegionChanged)
        qiniuRegionPopup.setAccessibilityLabel(L10n.tr("image_upload.field.region"))
        qiniuRegionPopup.widthAnchor.constraint(equalToConstant: 220).isActive = true

        pathStyleSwitch.controlSize = .small
        pathStyleSwitch.state = host.usePathStyle ? .on : .off
        pathStyleSwitch.setAccessibilityLabel(L10n.tr("image_upload.field.path_style"))

        let fields: [(NSTextField, String, String)] = [
            (nameField, host.name, "image_upload.field.name"),
            (bucketField, host.bucket, "image_upload.field.bucket"),
            (regionField, host.region, "image_upload.field.region"),
            (endpointField, host.endpoint, "image_upload.field.endpoint"),
            (accessKeyField, host.accessKey, "image_upload.field.access_key"),
            (secretKeyField, "", "image_upload.field.secret_key"),
            (domainField, host.domain, "image_upload.field.domain"),
            (saveKeyPathField, host.saveKeyPath, "image_upload.field.save_key_path"),
            (suffixField, host.suffix, "image_upload.field.suffix"),
        ]
        for (field, value, key) in fields {
            field.stringValue = value
            field.lineBreakMode = .byTruncatingMiddle
            field.setAccessibilityLabel(L10n.tr(key))
            field.delegate = self
            field.translatesAutoresizingMaskIntoConstraints = false
        }

        nameField.placeholderString = L10n.tr("image_upload.placeholder.name")
        bucketField.placeholderString = L10n.tr("image_upload.placeholder.bucket")
        saveKeyPathField.placeholderString = ImageHostConfig.defaultSaveKeyPath
        suffixField.placeholderString = L10n.tr("image_upload.placeholder.suffix")
        secretKeyField.placeholderString = hasStoredSecret
            ? L10n.tr("image_upload.placeholder.secret_key_saved")
            : L10n.tr("image_upload.placeholder.secret_key")

        for label in [regionLabel, endpointLabel, accessKeyLabel, secretKeyLabel, domainLabel] {
            label.font = SettingsStyle.rowTitleFont
            label.textColor = .labelColor
            label.translatesAutoresizingMaskIntoConstraints = false
        }
    }

    private func configureLayout() {
        sheetWindow.isReleasedWhenClosed = false
        let root = SettingsCanvasView(frame: NSRect(x: 0, y: 0, width: 520, height: 610))
        sheetWindow.contentView = root

        let titleText = editingHost == nil
            ? L10n.tr("image_upload.sheet.add_title")
            : L10n.tr("image_upload.sheet.edit_title")
        let heading = NSTextField(labelWithString: titleText)
        heading.font = .systemFont(ofSize: 16, weight: .semibold)
        heading.translatesAutoresizingMaskIntoConstraints = false

        let basicSection = SettingsSectionView(
            title: L10n.tr("image_upload.sheet.section.basic"),
            rows: [
                SettingsRowView(title: L10n.tr("image_upload.field.provider"), trailingViews: [providerPopup], verticalPadding: 9),
                fieldRow(title: L10n.tr("image_upload.field.name"), field: nameField),
            ]
        )

        let regionControl = NSStackView(views: [regionField, qiniuRegionPopup])
        regionControl.orientation = .horizontal
        regionControl.alignment = .centerY
        regionControl.spacing = 6
        regionControl.translatesAutoresizingMaskIntoConstraints = false

        bucketRowView = fieldRow(title: L10n.tr("image_upload.field.bucket"), field: bucketField)
        regionRowView = customFieldRow(label: regionLabel, control: regionControl)
        endpointRowView = customFieldRow(label: endpointLabel, control: endpointField)
        pathStyleRowView = SettingsRowView(
            title: L10n.tr("image_upload.field.path_style"),
            trailingViews: [pathStyleSwitch],
            verticalPadding: 9
        )
        accessKeyRowView = customFieldRow(label: accessKeyLabel, control: accessKeyField)
        secretKeyRowView = customFieldRow(label: secretKeyLabel, control: secretKeyField)

        let authHeader = NSTextField(labelWithString: L10n.tr("image_upload.sheet.section.auth"))
        authHeader.font = SettingsStyle.sectionTitleFont
        authHeader.textColor = SettingsStyle.secondaryText
        authHeader.translatesAutoresizingMaskIntoConstraints = false
        let authHeaderWrap = NSView()
        authHeaderWrap.translatesAutoresizingMaskIntoConstraints = false
        authHeaderWrap.addSubview(authHeader)
        NSLayoutConstraint.activate([
            authHeader.leadingAnchor.constraint(equalTo: authHeaderWrap.leadingAnchor, constant: 4),
            authHeader.trailingAnchor.constraint(equalTo: authHeaderWrap.trailingAnchor),
            authHeader.topAnchor.constraint(equalTo: authHeaderWrap.topAnchor),
            authHeader.bottomAnchor.constraint(equalTo: authHeaderWrap.bottomAnchor),
        ])

        let deliverySection = SettingsSectionView(
            title: L10n.tr("image_upload.sheet.section.delivery"),
            rows: [
                customFieldRow(label: domainLabel, control: domainField),
                fieldRow(title: L10n.tr("image_upload.field.save_key_path"), field: saveKeyPathField),
                fieldRow(title: L10n.tr("image_upload.field.suffix"), field: suffixField),
            ],
            footer: L10n.tr("image_upload.settings.template_note")
        )

        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.translatesAutoresizingMaskIntoConstraints = false

        let doc = SettingsFlippedView()
        doc.translatesAutoresizingMaskIntoConstraints = false
        scroll.documentView = doc

        let formStack = NSStackView(views: [basicSection, authHeaderWrap, authCard, deliverySection])
        formStack.orientation = .vertical
        formStack.alignment = .leading
        formStack.spacing = 12
        formStack.setCustomSpacing(6, after: authHeaderWrap)
        formStack.translatesAutoresizingMaskIntoConstraints = false
        doc.addSubview(formStack)

        cancelButton.target = self
        cancelButton.action = #selector(cancelClicked)
        cancelButton.keyEquivalent = "\u{1b}"

        saveButton.target = self
        saveButton.action = #selector(saveClicked)
        saveButton.keyEquivalent = "\r"

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let actions = NSStackView(views: [spacer, cancelButton, saveButton])
        actions.orientation = .horizontal
        actions.alignment = .centerY
        actions.spacing = 10
        actions.translatesAutoresizingMaskIntoConstraints = false

        let divider = SettingsHairlineView()

        root.addSubview(heading)
        root.addSubview(scroll)
        root.addSubview(errorBanner)
        root.addSubview(divider)
        root.addSubview(actions)

        NSLayoutConstraint.activate([
            heading.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 20),
            heading.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -20),
            heading.topAnchor.constraint(equalTo: root.topAnchor, constant: 18),

            scroll.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: heading.bottomAnchor, constant: 12),
            scroll.bottomAnchor.constraint(equalTo: errorBanner.topAnchor, constant: -8),
            doc.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),

            formStack.leadingAnchor.constraint(equalTo: doc.leadingAnchor, constant: 20),
            formStack.trailingAnchor.constraint(equalTo: doc.trailingAnchor, constant: -20),
            formStack.topAnchor.constraint(equalTo: doc.topAnchor, constant: 2),
            formStack.bottomAnchor.constraint(equalTo: doc.bottomAnchor, constant: -14),
            basicSection.widthAnchor.constraint(equalTo: formStack.widthAnchor),
            authCard.widthAnchor.constraint(equalTo: formStack.widthAnchor),
            deliverySection.widthAnchor.constraint(equalTo: formStack.widthAnchor),

            errorBanner.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 20),
            errorBanner.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -20),
            errorBanner.bottomAnchor.constraint(equalTo: divider.topAnchor, constant: -10),

            divider.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            divider.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            divider.bottomAnchor.constraint(equalTo: actions.topAnchor, constant: -12),

            actions.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 20),
            actions.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -20),
            actions.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -16),
        ])
    }

    private func fieldRow(title: String, field: NSView) -> NSView {
        let label = NSTextField(labelWithString: title)
        label.font = SettingsStyle.rowTitleFont
        label.textColor = .labelColor
        label.translatesAutoresizingMaskIntoConstraints = false
        return customFieldRow(label: label, control: field)
    }

    private func customFieldRow(label: NSTextField, control: NSView) -> NSView {
        label.widthAnchor.constraint(equalToConstant: 128).isActive = true
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(label)
        container.addSubview(control)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 14),
            label.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            control.leadingAnchor.constraint(equalTo: label.trailingAnchor, constant: 10),
            control.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -14),
            control.topAnchor.constraint(equalTo: container.topAnchor, constant: 9),
            control.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -9),
        ])
        return container
    }

    private func applyProviderAppearance(resettingProviderDefaults: Bool) {
        if resettingProviderDefaults {
            let template = ImageHostConfig.makeTemplate(for: currentProvider, name: nameField.stringValue)
            regionField.stringValue = template.region
            if currentProvider == .qiniu {
                endpointField.stringValue = ""
                let qRegion = QiniuRegion(rawValue: template.region) ?? .z0
                qiniuRegionPopup.selectItem(at: QiniuRegion.allCases.firstIndex(of: qRegion) ?? 0)
            }
            pathStyleSwitch.state = template.usePathStyle ? .on : .off
        }

        var authRows: [NSView] = [bucketRowView, regionRowView]
        switch currentProvider {
        case .s3:
            regionField.isHidden = false
            qiniuRegionPopup.isHidden = true
            regionField.placeholderString = "auto / us-east-1"
            endpointField.placeholderString = "https://<account>.r2.cloudflarestorage.com"
            accessKeyLabel.stringValue = L10n.tr("image_upload.field.access_key")
            secretKeyLabel.stringValue = L10n.tr("image_upload.field.secret_key")
            domainLabel.stringValue = L10n.tr("image_upload.field.domain")
            domainField.placeholderString = L10n.tr("image_upload.placeholder.domain_optional")
            authRows.append(contentsOf: [endpointRowView, pathStyleRowView])
        case .aliyunOSS:
            regionField.isHidden = false
            qiniuRegionPopup.isHidden = true
            regionField.placeholderString = "oss-cn-hangzhou"
            endpointField.placeholderString = L10n.tr("image_upload.placeholder.endpoint_optional")
            accessKeyLabel.stringValue = "AccessKey ID"
            secretKeyLabel.stringValue = "AccessKey Secret"
            domainLabel.stringValue = L10n.tr("image_upload.field.domain")
            domainField.placeholderString = L10n.tr("image_upload.placeholder.domain_optional")
            authRows.append(endpointRowView)
        case .tencentCOS:
            regionField.isHidden = false
            qiniuRegionPopup.isHidden = true
            regionField.placeholderString = "ap-guangzhou"
            endpointField.placeholderString = L10n.tr("image_upload.placeholder.endpoint_optional")
            accessKeyLabel.stringValue = "SecretId"
            secretKeyLabel.stringValue = "SecretKey"
            domainLabel.stringValue = L10n.tr("image_upload.field.domain")
            domainField.placeholderString = L10n.tr("image_upload.placeholder.domain_optional")
            authRows.append(endpointRowView)
        case .qiniu:
            regionField.isHidden = true
            qiniuRegionPopup.isHidden = false
            let qIndex = max(0, min(QiniuRegion.allCases.count - 1, qiniuRegionPopup.indexOfSelectedItem))
            let qRegion = QiniuRegion.allCases[qIndex]
            endpointField.placeholderString = "https://upload.qiniup.com"
            accessKeyLabel.stringValue = "AccessKey"
            secretKeyLabel.stringValue = "SecretKey"
            domainLabel.stringValue = L10n.tr("image_upload.field.domain_required")
            domainField.placeholderString = "https://cdn.example.com"
            if qRegion == .custom {
                authRows.append(endpointRowView)
            }
        }
        authRows.append(contentsOf: [accessKeyRowView, secretKeyRowView])
        authCard.setRows(authRows)
    }

    @objc private func providerChanged() {
        let index = max(0, min(ImageHostProvider.allCases.count - 1, providerPopup.indexOfSelectedItem))
        let next = ImageHostProvider.allCases[index]
        guard next != currentProvider else { return }
        currentProvider = next
        errorBanner.clear()
        applyProviderAppearance(resettingProviderDefaults: true)
    }

    @objc private func qiniuRegionChanged() {
        errorBanner.clear()
        applyProviderAppearance(resettingProviderDefaults: false)
    }

    @objc private func cancelClicked() {
        sheetWindow.makeFirstResponder(nil)
        parentWindow?.endSheet(sheetWindow, returnCode: .cancel)
        sheetWindow.orderOut(nil)
    }

    @objc private func saveClicked() {
        sheetWindow.makeFirstResponder(nil)
        let regionValue: String
        let endpointValue: String
        if currentProvider == .qiniu {
            let rIndex = max(0, min(QiniuRegion.allCases.count - 1, qiniuRegionPopup.indexOfSelectedItem))
            let qRegion = QiniuRegion.allCases[rIndex]
            regionValue = qRegion.rawValue
            endpointValue = qRegion == .custom ? endpointField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines) : ""
        } else {
            regionValue = regionField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            endpointValue = endpointField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let trimmedSavePath = saveKeyPathField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let candidate = ImageHostConfig(
            id: editingHost?.id ?? "host.\(UUID().uuidString)",
            name: nameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines),
            provider: currentProvider,
            bucket: bucketField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines),
            region: regionValue,
            endpoint: endpointValue,
            accessKey: accessKeyField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines),
            domain: domainField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines),
            saveKeyPath: trimmedSavePath.isEmpty ? ImageHostConfig.defaultSaveKeyPath : trimmedSavePath,
            suffix: suffixField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines),
            usePathStyle: currentProvider == .s3 ? (pathStyleSwitch.state == .on) : false
        )

        let enteredSecret = secretKeyField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let secretToSave: String? = enteredSecret.isEmpty ? nil : enteredSecret
        if secretToSave == nil && !hasStoredSecret {
            let displayName = candidate.name.isEmpty ? candidate.provider.title : candidate.name
            errorBanner.show(ImageUploadError.missingSecretKey(hostName: displayName).localizedDescription, level: .error)
            return
        }

        switch onCommit(candidate, secretToSave) {
        case .success:
            parentWindow?.endSheet(sheetWindow, returnCode: .OK)
            sheetWindow.orderOut(nil)
        case .failure(let error):
            errorBanner.show(error.localizedDescription, level: .error)
        }
    }
}

extension ImageHostEditorSheet: NSTextFieldDelegate {
    func controlTextDidChange(_ obj: Notification) {
        errorBanner.clear()
    }
}
