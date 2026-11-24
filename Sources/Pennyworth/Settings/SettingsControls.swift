import AppKit

/// Calm, actionable empty state displayed inside a card when a collection has no items.
@MainActor final class SettingsEmptyStateView: NSView {
    private let iconBadge = NSView()
    private let iconView = NSImageView()

    init(
        symbolName: String,
        title: String,
        subtitle: String,
        actionTitle: String? = nil,
        target: AnyObject? = nil,
        action: Selector? = nil
    ) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        iconBadge.wantsLayer = true
        iconBadge.layer?.cornerRadius = 12
        iconBadge.translatesAutoresizingMaskIntoConstraints = false

        let config = NSImage.SymbolConfiguration(pointSize: 18, weight: .medium)
        iconView.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?
            .withSymbolConfiguration(config)
        iconView.contentTintColor = .secondaryLabelColor
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconBadge.addSubview(iconView)

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 13.5, weight: .semibold)
        titleLabel.textColor = .labelColor
        titleLabel.alignment = .center

        let subtitleLabel = NSTextField(wrappingLabelWithString: subtitle)
        subtitleLabel.font = SettingsStyle.rowSubtitleFont
        subtitleLabel.textColor = .secondaryLabelColor
        subtitleLabel.alignment = .center
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false

        var views: [NSView] = [iconBadge, titleLabel, subtitleLabel]
        if let actionTitle {
            let cta = SettingsStyle.makeButton(title: actionTitle, symbolName: "plus", primary: true, target: target, action: action)
            views.append(cta)
        }

        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 8
        stack.setCustomSpacing(12, after: subtitleLabel)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            iconBadge.widthAnchor.constraint(equalToConstant: 40),
            iconBadge.heightAnchor.constraint(equalToConstant: 40),
            iconView.centerXAnchor.constraint(equalTo: iconBadge.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: iconBadge.centerYAnchor),
            subtitleLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 360),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -24),
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 28),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -28),
        ])

        applyAppearanceColors()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyAppearanceColors()
    }

    private func applyAppearanceColors() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            iconBadge.layer?.backgroundColor = SettingsStyle.badgeNeutralFill.cgColor
        }
    }
}

/// Dismissible semantic banner for instant-apply feedback, conflicts, warnings, and restart notices.
@MainActor final class SettingsStatusBanner: NSView {
    private let iconView = NSImageView()
    let messageLabel = NSTextField(wrappingLabelWithString: "")
    private let closeButton: SettingsIconButton
    private var level: SettingsStyle.StatusLevel = .info
    var onVisibilityChanged: ((Bool) -> Void)?

    var message: String { messageLabel.stringValue }

    init() {
        closeButton = SettingsIconButton(
            symbolName: "xmark",
            accessibilityLabel: L10n.tr("common.dismiss"),
            size: 22,
            pointSize: 10
        )
        super.init(frame: .zero)
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false
        layer?.cornerRadius = 8
        layer?.borderWidth = 1
        isHidden = true

        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.setContentHuggingPriority(.required, for: .horizontal)
        iconView.setContentCompressionResistancePriority(.required, for: .horizontal)

        messageLabel.font = .systemFont(ofSize: 12, weight: .regular)
        messageLabel.textColor = .labelColor
        messageLabel.translatesAutoresizingMaskIntoConstraints = false
        messageLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        closeButton.target = self
        closeButton.action = #selector(dismissClicked)

        addSubview(iconView)
        addSubview(messageLabel)
        addSubview(closeButton)

        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            iconView.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            iconView.widthAnchor.constraint(equalToConstant: 15),
            iconView.heightAnchor.constraint(equalToConstant: 15),
            messageLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 8),
            messageLabel.trailingAnchor.constraint(equalTo: closeButton.leadingAnchor, constant: -8),
            messageLabel.topAnchor.constraint(equalTo: topAnchor, constant: 9),
            messageLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -9),
            closeButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            closeButton.centerYAnchor.constraint(equalTo: iconView.centerYAnchor),
        ])
        applyAppearanceColors()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func show(_ text: String, level: SettingsStyle.StatusLevel) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            clear()
            return
        }
        self.level = level
        messageLabel.stringValue = trimmed
        let config = NSImage.SymbolConfiguration(pointSize: 13, weight: .medium)
        iconView.image = NSImage(systemSymbolName: SettingsStyle.statusSymbolName(for: level), accessibilityDescription: nil)?
            .withSymbolConfiguration(config)
        isHidden = false
        onVisibilityChanged?(true)
        applyAppearanceColors()
    }

    func clear() {
        messageLabel.stringValue = ""
        isHidden = true
        onVisibilityChanged?(false)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyAppearanceColors()
    }

    private func applyAppearanceColors() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = SettingsStyle.statusBackground(for: level).cgColor
            layer?.borderColor = SettingsStyle.statusBorder(for: level).cgColor
            iconView.contentTintColor = SettingsStyle.statusForeground(for: level)
        }
    }

    @objc private func dismissClicked() {
        clear()
    }
}

/// Hoverable icon button used for inline row actions (edit, delete, copy, dismiss).
@MainActor final class SettingsIconButton: NSButton {
    private let isDestructive: Bool
    private var isHovered = false
    private var tracking: NSTrackingArea?

    init(
        symbolName: String,
        accessibilityLabel: String,
        tooltip: String? = nil,
        isDestructive: Bool = false,
        size: CGFloat = 28,
        pointSize: CGFloat = 12.5,
        target: AnyObject? = nil,
        action: Selector? = nil
    ) {
        self.isDestructive = isDestructive
        super.init(frame: .zero)
        self.target = target
        self.action = action
        title = ""
        isBordered = false
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false
        layer?.cornerRadius = 6

        let config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .medium)
        image = NSImage(systemSymbolName: symbolName, accessibilityDescription: accessibilityLabel)?
            .withSymbolConfiguration(config)
        imagePosition = .imageOnly
        setAccessibilityLabel(accessibilityLabel)
        toolTip = tooltip ?? accessibilityLabel

        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: size),
            heightAnchor.constraint(equalToConstant: size),
        ])
        applyAppearanceColors()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        tracking = area
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        applyAppearanceColors()
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        applyAppearanceColors()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyAppearanceColors()
    }

    private func applyAppearanceColors() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            if isHovered, isEnabled {
                layer?.backgroundColor = (isDestructive ? SettingsStyle.destructiveHoverFill : SettingsStyle.rowHoverFill).cgColor
                contentTintColor = isDestructive ? .systemRed : .labelColor
            } else {
                layer?.backgroundColor = NSColor.clear.cgColor
                contentTintColor = .secondaryLabelColor
            }
        }
    }
}

/// Custom sidebar navigation button with quiet macOS styling (soft accent pill when selected, transparent at rest).
@MainActor final class SettingsSidebarItemView: NSButton {
    private let iconView = NSImageView()
    private let labelView = NSTextField(labelWithString: "")
    private var isHovered = false
    private var tracking: NSTrackingArea?

    override var state: NSControl.StateValue {
        didSet { applyAppearanceColors() }
    }

    init(title: String, symbolName: String, target: AnyObject?, action: Selector?) {
        super.init(frame: .zero)
        self.title = title
        self.target = target
        self.action = action
        isBordered = false
        setButtonType(.pushOnPushOff)
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false
        layer?.cornerRadius = 7
        layer?.borderWidth = 1

        let config = NSImage.SymbolConfiguration(pointSize: 13.5, weight: .medium)
        iconView.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?
            .withSymbolConfiguration(config)
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.setContentHuggingPriority(.required, for: .horizontal)

        labelView.stringValue = title
        labelView.lineBreakMode = .byTruncatingTail
        labelView.translatesAutoresizingMaskIntoConstraints = false

        addSubview(iconView)
        addSubview(labelView)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 32),
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 18),
            iconView.heightAnchor.constraint(equalToConstant: 18),
            labelView.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 8),
            labelView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            labelView.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])

        setAccessibilityLabel(L10n.format("settings.page_accessibility", title))
        applyAppearanceColors()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    // Custom subviews render the icon and label cleanly; suppress NSButtonCell text drawing.
    override func draw(_ dirtyRect: NSRect) {}

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        tracking = area
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        applyAppearanceColors()
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        applyAppearanceColors()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyAppearanceColors()
    }

    private func applyAppearanceColors() {
        let selected = state == .on
        labelView.font = selected ? SettingsStyle.sidebarItemSelectedFont : SettingsStyle.sidebarItemFont
        effectiveAppearance.performAsCurrentDrawingAppearance {
            if selected {
                layer?.backgroundColor = SettingsStyle.sidebarSelectedFill.cgColor
                layer?.borderColor = SettingsStyle.sidebarSelectedBorder.cgColor
                iconView.contentTintColor = PennyworthTheme.accentPrimary
                labelView.textColor = .labelColor
            } else if isHovered {
                layer?.backgroundColor = SettingsStyle.sidebarHoverFill.cgColor
                layer?.borderColor = NSColor.clear.cgColor
                iconView.contentTintColor = .labelColor
                labelView.textColor = .labelColor
            } else {
                layer?.backgroundColor = NSColor.clear.cgColor
                layer?.borderColor = NSColor.clear.cgColor
                iconView.contentTintColor = .secondaryLabelColor
                labelView.textColor = .labelColor
            }
        }
    }
}
