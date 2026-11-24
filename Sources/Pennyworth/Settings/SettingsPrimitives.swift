import AppKit

/// Flipped container for scroll document hosts and top-down layouts.
@MainActor final class SettingsFlippedView: NSView {
    override var isFlipped: Bool { true }
}

/// Canvas surface that matches the macOS grouped-settings background across appearances.
@MainActor final class SettingsCanvasView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
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
            layer?.backgroundColor = SettingsStyle.canvasBackground.cgColor
        }
    }
}

/// 1pt dynamic hairline divider used inside cards and between window panes.
@MainActor final class SettingsHairlineView: NSView {
    private let vertical: Bool

    init(vertical: Bool = false) {
        self.vertical = vertical
        super.init(frame: .zero)
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false
        if vertical {
            widthAnchor.constraint(equalToConstant: 1).isActive = true
        } else {
            heightAnchor.constraint(equalToConstant: 1).isActive = true
        }
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
            layer?.backgroundColor = (vertical ? SettingsStyle.paneDivider : SettingsStyle.dividerHairline).cgColor
        }
    }
}

/// Appearance-aware rounded icon badge for leading row SF Symbols.
@MainActor final class SettingsIconBadgeView: NSView {
    private let iconView = NSImageView()
    private let accented: Bool

    init(symbolName: String, accented: Bool = false, size: CGFloat = 32, pointSize: CGFloat = 15) {
        self.accented = accented
        super.init(frame: .zero)
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false
        layer?.cornerRadius = 8

        let config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .medium)
        iconView.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?
            .withSymbolConfiguration(config)
        iconView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(iconView)

        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: size),
            heightAnchor.constraint(equalToConstant: size),
            iconView.centerXAnchor.constraint(equalTo: centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
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
            layer?.backgroundColor = (accented ? PennyworthTheme.badgeAccentFill : SettingsStyle.badgeNeutralFill).cgColor
            iconView.contentTintColor = accented ? PennyworthTheme.accentPrimary : .secondaryLabelColor
        }
    }
}

/// Compact pill badge for tags ("Built-in", "Default", "bm", "Always On", etc.).
@MainActor final class SettingsBadgeLabel: NSView {
    enum Tone {
        case neutral
        case accent
        case success
        case warning
        case error
    }

    private let textLabel = NSTextField(labelWithString: "")
    private var tone: Tone

    init(text: String, tone: Tone = .neutral, monospaced: Bool = false, minWidth: CGFloat? = nil) {
        self.tone = tone
        super.init(frame: .zero)
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false
        layer?.cornerRadius = 6
        layer?.borderWidth = 1

        textLabel.stringValue = text
        textLabel.font = monospaced ? SettingsStyle.monoKeycapFont : SettingsStyle.badgeFont
        textLabel.alignment = .center
        textLabel.lineBreakMode = .byTruncatingTail
        textLabel.translatesAutoresizingMaskIntoConstraints = false
        textLabel.setContentHuggingPriority(.required, for: .horizontal)
        textLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        addSubview(textLabel)

        var constraints: [NSLayoutConstraint] = [
            textLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            textLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            textLabel.topAnchor.constraint(equalTo: topAnchor, constant: 3),
            textLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -3),
        ]
        if let minWidth {
            constraints.append(widthAnchor.constraint(greaterThanOrEqualToConstant: minWidth))
        }
        NSLayoutConstraint.activate(constraints)
        setContentHuggingPriority(.required, for: .horizontal)
        setContentCompressionResistancePriority(.required, for: .horizontal)
        applyAppearanceColors()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func update(text: String, tone: Tone? = nil) {
        textLabel.stringValue = text
        if let tone { self.tone = tone }
        isHidden = text.isEmpty
        applyAppearanceColors()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyAppearanceColors()
    }

    private func applyAppearanceColors() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            switch tone {
            case .neutral:
                layer?.backgroundColor = SettingsStyle.badgeNeutralFill.cgColor
                layer?.borderColor = SettingsStyle.cardBorder.cgColor
                textLabel.textColor = .secondaryLabelColor
            case .accent:
                layer?.backgroundColor = PennyworthTheme.badgeAccentFill.cgColor
                layer?.borderColor = PennyworthTheme.selectionBorder.cgColor
                textLabel.textColor = PennyworthTheme.accentPrimary
            case .success:
                layer?.backgroundColor = SettingsStyle.statusBackground(for: .success).cgColor
                layer?.borderColor = SettingsStyle.statusBorder(for: .success).cgColor
                textLabel.textColor = .systemGreen
            case .warning:
                layer?.backgroundColor = SettingsStyle.statusBackground(for: .warning).cgColor
                layer?.borderColor = SettingsStyle.statusBorder(for: .warning).cgColor
                textLabel.textColor = .systemOrange
            case .error:
                layer?.backgroundColor = SettingsStyle.statusBackground(for: .error).cgColor
                layer?.borderColor = SettingsStyle.statusBorder(for: .error).cgColor
                textLabel.textColor = .systemRed
            }
        }
    }
}

/// Rounded grouped-settings card that separates stacked rows with indented hairlines.
@MainActor final class SettingsCardView: NSView {
    private let stack = NSStackView()

    init(rows: [NSView] = []) {
        super.init(frame: .zero)
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false
        layer?.cornerRadius = SettingsStyle.cardCornerRadius
        layer?.borderWidth = 1
        layer?.masksToBounds = true

        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        setRows(rows)
        applyAppearanceColors()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func setRows(_ rows: [NSView]) {
        for view in stack.arrangedSubviews {
            stack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        for (index, row) in rows.enumerated() {
            if index > 0 {
                let dividerHost = NSView()
                dividerHost.translatesAutoresizingMaskIntoConstraints = false
                let divider = SettingsHairlineView()
                dividerHost.addSubview(divider)
                NSLayoutConstraint.activate([
                    divider.leadingAnchor.constraint(equalTo: dividerHost.leadingAnchor, constant: SettingsStyle.rowHorizontalPadding),
                    divider.trailingAnchor.constraint(equalTo: dividerHost.trailingAnchor, constant: -SettingsStyle.rowHorizontalPadding),
                    divider.topAnchor.constraint(equalTo: dividerHost.topAnchor),
                    divider.bottomAnchor.constraint(equalTo: dividerHost.bottomAnchor),
                ])
                stack.addArrangedSubview(dividerHost)
                dividerHost.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
            }
            row.translatesAutoresizingMaskIntoConstraints = false
            stack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyAppearanceColors()
    }

    private func applyAppearanceColors() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = SettingsStyle.cardBackground.cgColor
            layer?.borderColor = SettingsStyle.cardBorder.cgColor
        }
    }
}

/// Standard horizontal macOS settings row with optional leading view, title/subtitle, and trailing controls.
@MainActor final class SettingsRowView: NSView {
    let titleLabel: NSTextField
    let subtitleLabel: NSTextField?

    init(
        title: String,
        subtitle: String? = nil,
        leadingView: NSView? = nil,
        trailingViews: [NSView] = [],
        titleBadges: [NSView] = [],
        dimmed: Bool = false,
        verticalPadding: CGFloat? = nil
    ) {
        let resolvedVerticalPadding = verticalPadding ?? SettingsStyle.rowVerticalPadding
        titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = SettingsStyle.rowTitleFont
        titleLabel.textColor = dimmed ? .secondaryLabelColor : .labelColor
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        if let subtitle, !subtitle.isEmpty {
            let sub = NSTextField(wrappingLabelWithString: subtitle)
            sub.font = SettingsStyle.rowSubtitleFont
            sub.textColor = dimmed ? .tertiaryLabelColor : SettingsStyle.secondaryText
            sub.lineBreakMode = .byTruncatingMiddle
            sub.maximumNumberOfLines = 2
            sub.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            subtitleLabel = sub
        } else {
            subtitleLabel = nil
        }

        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        let titleRow: NSView
        if titleBadges.isEmpty {
            titleRow = titleLabel
        } else {
            let badgeRow = NSStackView(views: [titleLabel] + titleBadges)
            badgeRow.orientation = .horizontal
            badgeRow.alignment = .centerY
            badgeRow.spacing = 6
            titleRow = badgeRow
        }

        let textViews: [NSView] = subtitleLabel.map { [titleRow, $0] } ?? [titleRow]
        let textStack = NSStackView(views: textViews)
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 2
        textStack.translatesAutoresizingMaskIntoConstraints = false
        textStack.setContentHuggingPriority(.defaultLow, for: .horizontal)
        textStack.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let leftStack: NSView
        if let leadingView {
            leadingView.translatesAutoresizingMaskIntoConstraints = false
            leadingView.setContentHuggingPriority(.required, for: .horizontal)
            leadingView.setContentCompressionResistancePriority(.required, for: .horizontal)
            let combined = NSStackView(views: [leadingView, textStack])
            combined.orientation = .horizontal
            combined.alignment = .centerY
            combined.spacing = 11
            combined.translatesAutoresizingMaskIntoConstraints = false
            combined.setContentHuggingPriority(.defaultLow, for: .horizontal)
            combined.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            leftStack = combined
        } else {
            leftStack = textStack
        }

        addSubview(leftStack)

        var constraints: [NSLayoutConstraint] = [
            leftStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: SettingsStyle.rowHorizontalPadding),
            leftStack.centerYAnchor.constraint(equalTo: centerYAnchor),
            leftStack.topAnchor.constraint(greaterThanOrEqualTo: topAnchor, constant: resolvedVerticalPadding),
            leftStack.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -resolvedVerticalPadding),
            heightAnchor.constraint(greaterThanOrEqualToConstant: subtitleLabel == nil ? 44 : 54),
        ]

        if trailingViews.isEmpty {
            constraints.append(
                leftStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -SettingsStyle.rowHorizontalPadding)
            )
        } else {
            let trailingStack = NSStackView(views: trailingViews)
            trailingStack.orientation = .horizontal
            trailingStack.alignment = .centerY
            trailingStack.spacing = 8
            trailingStack.translatesAutoresizingMaskIntoConstraints = false
            trailingStack.setContentHuggingPriority(.required, for: .horizontal)
            trailingStack.setContentCompressionResistancePriority(.required, for: .horizontal)
            for view in trailingViews {
                view.setContentCompressionResistancePriority(.required, for: .horizontal)
            }
            addSubview(trailingStack)

            constraints.append(contentsOf: [
                trailingStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -SettingsStyle.rowHorizontalPadding),
                trailingStack.centerYAnchor.constraint(equalTo: centerYAnchor),
                trailingStack.topAnchor.constraint(greaterThanOrEqualTo: topAnchor, constant: 8),
                trailingStack.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -8),
                leftStack.trailingAnchor.constraint(lessThanOrEqualTo: trailingStack.leadingAnchor, constant: -16),
            ])
        }

        NSLayoutConstraint.activate(constraints)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
}

/// Section container combining an optional header (with optional action), a grouped card, and an optional footnote.
@MainActor final class SettingsSectionView: NSView {
    let card: SettingsCardView

    init(
        title: String? = nil,
        headerAccessory: NSView? = nil,
        rows: [NSView] = [],
        footer: String? = nil
    ) {
        card = SettingsCardView(rows: rows)
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        var arranged: [NSView] = []
        if title != nil || headerAccessory != nil {
            let header = NSView()
            header.translatesAutoresizingMaskIntoConstraints = false
            var headerConstraints: [NSLayoutConstraint] = []

            if let title {
                let label = NSTextField(labelWithString: title)
                label.font = SettingsStyle.sectionTitleFont
                label.textColor = SettingsStyle.secondaryText
                label.translatesAutoresizingMaskIntoConstraints = false
                header.addSubview(label)
                headerConstraints.append(contentsOf: [
                    label.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 4),
                    label.centerYAnchor.constraint(equalTo: header.centerYAnchor),
                    label.topAnchor.constraint(greaterThanOrEqualTo: header.topAnchor),
                    label.bottomAnchor.constraint(lessThanOrEqualTo: header.bottomAnchor),
                ])
            }
            if let headerAccessory {
                headerAccessory.translatesAutoresizingMaskIntoConstraints = false
                header.addSubview(headerAccessory)
                headerConstraints.append(contentsOf: [
                    headerAccessory.trailingAnchor.constraint(equalTo: header.trailingAnchor),
                    headerAccessory.centerYAnchor.constraint(equalTo: header.centerYAnchor),
                    headerAccessory.topAnchor.constraint(greaterThanOrEqualTo: header.topAnchor),
                    headerAccessory.bottomAnchor.constraint(lessThanOrEqualTo: header.bottomAnchor),
                ])
            }
            headerConstraints.append(header.heightAnchor.constraint(greaterThanOrEqualToConstant: 20))
            NSLayoutConstraint.activate(headerConstraints)
            arranged.append(header)
        }

        arranged.append(card)

        if let footer, !footer.isEmpty {
            let note = NSTextField(wrappingLabelWithString: footer)
            note.font = SettingsStyle.footnoteFont
            note.textColor = SettingsStyle.secondaryText
            note.translatesAutoresizingMaskIntoConstraints = false
            let noteContainer = NSView()
            noteContainer.translatesAutoresizingMaskIntoConstraints = false
            noteContainer.addSubview(note)
            NSLayoutConstraint.activate([
                note.leadingAnchor.constraint(equalTo: noteContainer.leadingAnchor, constant: 4),
                note.trailingAnchor.constraint(equalTo: noteContainer.trailingAnchor, constant: -4),
                note.topAnchor.constraint(equalTo: noteContainer.topAnchor, constant: 2),
                note.bottomAnchor.constraint(equalTo: noteContainer.bottomAnchor),
            ])
            arranged.append(noteContainer)
        }

        let stack = NSStackView(views: arranged)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        for view in arranged {
            view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
}
