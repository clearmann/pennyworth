import AppKit

/// Single-layer translucent panel surface with a crisp dynamic hairline border.
@MainActor final class FloatingPanelRootView: NSVisualEffectView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        material = .popover
        state = .active
        wantsLayer = true
        layer?.cornerRadius = PennyworthTheme.panelCornerRadius
        layer?.borderWidth = 1
        layer?.masksToBounds = true
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
            layer?.borderColor = PennyworthTheme.borderHairline.cgColor
        }
    }
}

/// Shared layout helpers for floating launcher and clipboard panels.
@MainActor enum FloatingPanelChrome {
    static func configureResultsTable(
        _ tableView: NSTableView,
        in scrollView: NSScrollView,
        columnIdentifier: String,
        width: CGFloat,
        accessibilityLabel: String
    ) {
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(columnIdentifier))
        column.width = width
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.rowHeight = PennyworthTheme.rowHeight
        tableView.intercellSpacing = .zero
        tableView.backgroundColor = .clear
        tableView.selectionHighlightStyle = .none
        tableView.style = .plain
        tableView.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        tableView.setAccessibilityLabel(accessibilityLabel)
        scrollView.documentView = tableView
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
    }
}

/// Subtle 1pt divider aligned with the floating panel's hairline token.
@MainActor final class HairlineDividerView: NSView {
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
            layer?.backgroundColor = PennyworthTheme.borderHairline.cgColor
        }
    }
}

/// Compact rounded pill used for mode tags, keyboard hints, and action keycaps.
@MainActor final class KeycapBadgeView: NSView {
    enum Style {
        case neutral
        case accent
    }

    private let label = NSTextField(labelWithString: "")
    private var style: Style
    var onTap: (() -> Void)?

    init(text: String = "", style: Style = .neutral, monospaced: Bool = false) {
        self.style = style
        super.init(frame: .zero)
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false
        layer?.cornerRadius = PennyworthTheme.badgeCornerRadius
        layer?.borderWidth = 1
        label.stringValue = text
        label.font = monospaced ? PennyworthTheme.monoBadgeFont : PennyworthTheme.badgeFont
        label.lineBreakMode = .byTruncatingTail
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        label.setContentCompressionResistancePriority(.required, for: .horizontal)
        label.setContentHuggingPriority(.required, for: .horizontal)
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            label.topAnchor.constraint(equalTo: topAnchor, constant: 3),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -3),
        ])
        let click = NSClickGestureRecognizer(target: self, action: #selector(handleClick))
        addGestureRecognizer(click)
        applyAppearanceColors()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func update(text: String, style: Style? = nil, accessibilityLabel: String? = nil) {
        label.stringValue = text
        if let style { self.style = style }
        if let accessibilityLabel { setAccessibilityLabel(accessibilityLabel) }
        isHidden = text.isEmpty
        applyAppearanceColors()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyAppearanceColors()
    }

    @objc private func handleClick() {
        onTap?()
    }

    private func applyAppearanceColors() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            switch style {
            case .neutral:
                layer?.backgroundColor = PennyworthTheme.surfaceElevated.cgColor
                layer?.borderColor = PennyworthTheme.borderHairline.cgColor
                label.textColor = .secondaryLabelColor
            case .accent:
                layer?.backgroundColor = PennyworthTheme.badgeAccentFill.cgColor
                layer?.borderColor = PennyworthTheme.selectionBorder.cgColor
                label.textColor = PennyworthTheme.accentPrimary
            }
        }
    }
}

/// Shared search header with leading symbol, borderless search input, trailing badge, and hairline divider.
@MainActor final class SearchHeaderView: NSView {
    static let height: CGFloat = 58
    let badge = KeycapBadgeView(style: .neutral, monospaced: true)

    init(symbolName: String, searchField: NSTextField) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        let iconView = NSImageView()
        iconView.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)
        iconView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 16, weight: .medium)
        iconView.contentTintColor = .secondaryLabelColor
        iconView.translatesAutoresizingMaskIntoConstraints = false
        searchField.translatesAutoresizingMaskIntoConstraints = false
        searchField.font = PennyworthTheme.searchFont
        searchField.isBezeled = false
        searchField.drawsBackground = false
        searchField.focusRingType = .none
        searchField.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let divider = HairlineDividerView()
        addSubview(iconView)
        addSubview(searchField)
        addSubview(badge)
        addSubview(divider)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: Self.height),
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 18),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -1),
            iconView.widthAnchor.constraint(equalToConstant: 20),
            iconView.heightAnchor.constraint(equalToConstant: 20),
            searchField.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 12),
            searchField.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -1),
            searchField.trailingAnchor.constraint(equalTo: badge.leadingAnchor, constant: -10),
            badge.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            badge.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -1),
            divider.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            divider.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            divider.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
}

/// Shared bottom footer displaying the status message and an Esc dismiss keycap hint.
@MainActor final class StatusFooterView: NSView {
    static let height: CGFloat = 36
    private let escapeBadge = KeycapBadgeView(text: "Esc", style: .neutral, monospaced: true)

    init(statusLabel: NSTextField) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        let divider = HairlineDividerView()
        statusLabel.font = PennyworthTheme.statusFont
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.lineBreakMode = .byTruncatingTail
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        addSubview(divider)
        addSubview(statusLabel)
        addSubview(escapeBadge)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: Self.height),
            divider.topAnchor.constraint(equalTo: topAnchor),
            divider.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            divider.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            statusLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 18),
            statusLabel.centerYAnchor.constraint(equalTo: centerYAnchor, constant: 1),
            statusLabel.trailingAnchor.constraint(lessThanOrEqualTo: escapeBadge.leadingAnchor, constant: -10),
            escapeBadge.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            escapeBadge.centerYAnchor.constraint(equalTo: centerYAnchor, constant: 1),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
}

/// Card-styled result cell shared by the launcher and clipboard history panels.
@MainActor final class ResultCellView: NSTableCellView {
    private let cardBackground = NSView()
    private let accentBar = NSView()
    private let iconContainer = NSView()
    private let subtitle = NSTextField(labelWithString: "")
    private let actionBadge = KeycapBadgeView(style: .accent, monospaced: true)
    private var isRowSelected = false
    private var usesSymbolSlot = false

    init(identifier: NSUserInterfaceItemIdentifier) {
        super.init(frame: .zero)
        self.identifier = identifier
        cardBackground.wantsLayer = true
        cardBackground.layer?.cornerRadius = PennyworthTheme.cardCornerRadius
        cardBackground.layer?.borderWidth = 1
        accentBar.wantsLayer = true
        accentBar.layer?.cornerRadius = 1.5
        iconContainer.wantsLayer = true
        iconContainer.layer?.cornerRadius = PennyworthTheme.iconCornerRadius
        let image = NSImageView()
        image.imageScaling = .scaleProportionallyDown
        let title = NSTextField(labelWithString: "")
        title.font = PennyworthTheme.rowTitleFont
        title.lineBreakMode = .byTruncatingTail
        subtitle.font = PennyworthTheme.rowSubtitleFont
        subtitle.textColor = .secondaryLabelColor
        subtitle.lineBreakMode = .byTruncatingMiddle
        [cardBackground, accentBar, iconContainer, title, subtitle, actionBadge].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            addSubview($0)
        }
        image.translatesAutoresizingMaskIntoConstraints = false
        iconContainer.addSubview(image)
        NSLayoutConstraint.activate([
            cardBackground.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            cardBackground.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            cardBackground.topAnchor.constraint(equalTo: topAnchor, constant: 3),
            cardBackground.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -3),
            accentBar.leadingAnchor.constraint(equalTo: cardBackground.leadingAnchor, constant: 4),
            accentBar.centerYAnchor.constraint(equalTo: cardBackground.centerYAnchor),
            accentBar.widthAnchor.constraint(equalToConstant: 3),
            accentBar.heightAnchor.constraint(equalToConstant: 24),
            iconContainer.leadingAnchor.constraint(equalTo: cardBackground.leadingAnchor, constant: 12),
            iconContainer.centerYAnchor.constraint(equalTo: cardBackground.centerYAnchor),
            iconContainer.widthAnchor.constraint(equalToConstant: 34),
            iconContainer.heightAnchor.constraint(equalToConstant: 34),
            image.centerXAnchor.constraint(equalTo: iconContainer.centerXAnchor),
            image.centerYAnchor.constraint(equalTo: iconContainer.centerYAnchor),
            image.widthAnchor.constraint(equalToConstant: 28),
            image.heightAnchor.constraint(equalToConstant: 28),
            title.leadingAnchor.constraint(equalTo: iconContainer.trailingAnchor, constant: 12),
            title.topAnchor.constraint(equalTo: cardBackground.topAnchor, constant: 7),
            title.trailingAnchor.constraint(lessThanOrEqualTo: actionBadge.leadingAnchor, constant: -10),
            subtitle.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            subtitle.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 2),
            subtitle.trailingAnchor.constraint(lessThanOrEqualTo: actionBadge.leadingAnchor, constant: -10),
            actionBadge.trailingAnchor.constraint(equalTo: cardBackground.trailingAnchor, constant: -12),
            actionBadge.centerYAnchor.constraint(equalTo: cardBackground.centerYAnchor),
        ])
        imageView = image
        textField = title
        applyAppearanceColors()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyAppearanceColors()
    }

    func configure(_ result: SearchResult, icon: NSImage?, selected: Bool,
                   usesSymbolBackground: Bool = false, actionBadgeText: String? = nil) {
        isRowSelected = selected
        usesSymbolSlot = usesSymbolBackground
        textField?.stringValue = result.title
        subtitle.stringValue = result.subtitle
        imageView?.image = icon
        imageView?.symbolConfiguration = usesSymbolBackground
            ? NSImage.SymbolConfiguration(pointSize: 16, weight: .medium)
            : nil
        imageView?.contentTintColor = usesSymbolBackground
            ? (selected ? PennyworthTheme.accentPrimary : .secondaryLabelColor)
            : nil
        accentBar.isHidden = !selected
        let badgeText = actionBadgeText ?? PennyworthTheme.actionKeycapTitle(for: result.action)
        actionBadge.update(text: selected ? badgeText : "", style: .accent)
        setAccessibilityLabel("\(result.title)，\(result.subtitle)")
        applyAppearanceColors()
    }

    private func applyAppearanceColors() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            cardBackground.layer?.backgroundColor = isRowSelected
                ? PennyworthTheme.selectionFill.cgColor
                : NSColor.clear.cgColor
            cardBackground.layer?.borderColor = isRowSelected
                ? PennyworthTheme.selectionBorder.cgColor
                : NSColor.clear.cgColor
            accentBar.layer?.backgroundColor = PennyworthTheme.accentPrimary.cgColor
            iconContainer.layer?.backgroundColor = usesSymbolSlot
                ? PennyworthTheme.surfaceElevated.cgColor
                : NSColor.clear.cgColor
        }
    }
}
