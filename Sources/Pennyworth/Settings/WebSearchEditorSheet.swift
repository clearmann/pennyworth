import AppKit

/// Modal sheet for creating or editing a custom web search definition with inline validation.
@MainActor final class WebSearchEditorSheet: NSObject {
    let sheetWindow: NSWindow
    private let keywordField = NSTextField()
    private let titleField = NSTextField()
    private let templateField = NSTextField()
    private let errorBanner = SettingsStatusBanner()
    private let cancelButton: NSButton
    private let saveButton: NSButton

    private let editingDefinition: WebSearchDefinition?
    private weak var parentWindow: NSWindow?
    private let onCommit: (WebSearchDefinition) -> Result<Void, Error>
    private let onDismiss: () -> Void

    init(
        editing: WebSearchDefinition?,
        onCommit: @escaping (WebSearchDefinition) -> Result<Void, Error>,
        onDismiss: @escaping () -> Void
    ) {
        self.editingDefinition = editing
        self.onCommit = onCommit
        self.onDismiss = onDismiss
        self.sheetWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 468, height: 310),
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
        configureUI()
    }

    func present(on window: NSWindow) {
        parentWindow = window
        window.beginSheet(sheetWindow) { [weak self] _ in
            self?.sheetWindow.makeFirstResponder(nil)
            self?.onDismiss()
        }
        sheetWindow.makeFirstResponder(keywordField)
    }

    private func configureUI() {
        sheetWindow.isReleasedWhenClosed = false
        let root = SettingsCanvasView(frame: NSRect(x: 0, y: 0, width: 468, height: 310))
        sheetWindow.contentView = root

        let headingText = editingDefinition == nil
            ? L10n.tr("web_search.sheet.add_title")
            : L10n.tr("web_search.sheet.edit_title")
        let titleLabel = NSTextField(labelWithString: headingText)
        titleLabel.font = .systemFont(ofSize: 16, weight: .semibold)

        configureField(keywordField, value: editingDefinition?.keyword ?? "",
                       placeholder: L10n.tr("web_search.keyword_example"),
                       accessibility: L10n.tr("web_search.keyword_accessibility"))
        configureField(titleField, value: editingDefinition?.title ?? "",
                       placeholder: L10n.tr("web_search.title_example"),
                       accessibility: L10n.tr("web_search.title_accessibility"))
        configureField(templateField, value: editingDefinition?.urlTemplate ?? "",
                       placeholder: "https://github.com/search?q={query}",
                       accessibility: L10n.tr("web_search.template_accessibility"))

        let formCard = SettingsCardView(rows: [
            formRow(L10n.tr("web_search.keyword"), field: keywordField),
            formRow(L10n.tr("web_search.display_name"), field: titleField),
            formRow(L10n.tr("web_search.url"), field: templateField),
        ])

        let hint = NSTextField(wrappingLabelWithString: L10n.tr("web_search.sheet.url_hint"))
        hint.font = SettingsStyle.footnoteFont
        hint.textColor = .secondaryLabelColor

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

        let stack = NSStackView(views: [titleLabel, formCard, hint, errorBanner, actions])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -20),
            stack.topAnchor.constraint(equalTo: root.topAnchor, constant: 20),
            stack.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -18),
            formCard.widthAnchor.constraint(equalTo: stack.widthAnchor),
            hint.widthAnchor.constraint(equalTo: stack.widthAnchor),
            errorBanner.widthAnchor.constraint(equalTo: stack.widthAnchor),
            actions.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])
    }

    private func configureField(
        _ field: NSTextField,
        value: String,
        placeholder: String,
        accessibility: String
    ) {
        field.stringValue = value
        field.placeholderString = placeholder
        field.lineBreakMode = .byTruncatingMiddle
        field.setAccessibilityLabel(accessibility)
        field.translatesAutoresizingMaskIntoConstraints = false
        field.delegate = self
    }

    private func formRow(_ labelText: String, field: NSTextField) -> NSView {
        let label = NSTextField(labelWithString: labelText)
        label.font = SettingsStyle.rowTitleFont
        label.textColor = .labelColor
        label.translatesAutoresizingMaskIntoConstraints = false
        label.widthAnchor.constraint(equalToConstant: 86).isActive = true

        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(label)
        container.addSubview(field)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 14),
            label.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            field.leadingAnchor.constraint(equalTo: label.trailingAnchor, constant: 10),
            field.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -14),
            field.topAnchor.constraint(equalTo: container.topAnchor, constant: 10),
            field.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -10),
        ])
        return container
    }

    @objc private func cancelClicked() {
        sheetWindow.makeFirstResponder(nil)
        parentWindow?.endSheet(sheetWindow, returnCode: .cancel)
        sheetWindow.orderOut(nil)
    }

    @objc private func saveClicked() {
        sheetWindow.makeFirstResponder(nil)
        let candidate = WebSearchDefinition(
            id: editingDefinition?.id ?? "custom.\(UUID().uuidString)",
            keyword: keywordField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines),
            title: titleField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines),
            urlTemplate: templateField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines),
            isEnabled: editingDefinition?.isEnabled ?? true,
            isCustom: true
        )
        switch onCommit(candidate) {
        case .success:
            parentWindow?.endSheet(sheetWindow, returnCode: .OK)
            sheetWindow.orderOut(nil)
        case .failure(let error):
            errorBanner.show(error.localizedDescription, level: .error)
        }
    }
}

extension WebSearchEditorSheet: NSTextFieldDelegate {
    func controlTextDidChange(_ obj: Notification) {
        errorBanner.clear()
    }
}
