import AppKit

/// Card-based Chrome bookmark import & matching preferences view.
@MainActor final class BookmarksSettingsView: NSView {
    let enabledSwitch = NSSwitch()
    let includeInDefaultSwitch = NSSwitch()
    let matchTitleCheckbox = NSButton(checkboxWithTitle: L10n.tr("settings.bookmarks.match_title"), target: nil, action: nil)
    let matchURLCheckbox = NSButton(checkboxWithTitle: L10n.tr("settings.bookmarks.match_url"), target: nil, action: nil)
    let matchFoldersCheckbox = NSButton(checkboxWithTitle: L10n.tr("settings.bookmarks.match_folders"), target: nil, action: nil)

    private let profilesCard = SettingsCardView()
    private let statusLabel = NSTextField(wrappingLabelWithString: L10n.tr("settings.bookmarks.not_imported"))
    private let detectButton: NSButton
    private let chooseDirectoryButton: NSButton
    private let refreshButton: NSButton
    private let clearButton: NSButton

    var onPreferenceChanged: ((BookmarkPreferences) -> Void)?
    var onProfileToggled: ((String, Bool) -> Void)?
    var onDetectProfiles: (() -> Void)?
    var onChooseDirectory: (() -> Void)?
    var onRefreshBookmarks: (() -> Void)?
    var onClearBookmarks: (() -> Void)?

    private var currentPreferences = BookmarkPreferences()

    init() {
        detectButton = SettingsStyle.makeButton(
            title: L10n.tr("settings.bookmarks.detect"),
            primary: false,
            target: nil,
            action: nil
        )
        chooseDirectoryButton = SettingsStyle.makeButton(
            title: L10n.tr("settings.bookmarks.choose_directory"),
            primary: false,
            target: nil,
            action: nil
        )
        refreshButton = SettingsStyle.makeButton(
            title: L10n.tr("settings.bookmarks.import_refresh"),
            symbolName: "arrow.clockwise",
            primary: true,
            target: nil,
            action: nil
        )
        clearButton = SettingsStyle.makeButton(
            title: L10n.tr("settings.bookmarks.clear"),
            primary: false,
            target: nil,
            action: nil
        )
        super.init(frame: .zero)
        configure()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func reload(bookmarks: BookmarkStore?, busy: Bool) {
        let prefs = bookmarks?.preferences ?? BookmarkPreferences()
        currentPreferences = prefs

        enabledSwitch.state = prefs.enabled ? .on : .off
        includeInDefaultSwitch.state = prefs.includeInDefaultResults ? .on : .off
        matchTitleCheckbox.state = prefs.matchTitle ? .on : .off
        matchURLCheckbox.state = prefs.matchURL ? .on : .off
        matchFoldersCheckbox.state = prefs.matchFolders ? .on : .off

        let controlsEnabled = bookmarks != nil && !busy
        for control in [enabledSwitch, includeInDefaultSwitch] as [NSControl] {
            control.isEnabled = controlsEnabled
        }
        for button in [matchTitleCheckbox, matchURLCheckbox, matchFoldersCheckbox,
                       detectButton, chooseDirectoryButton, refreshButton, clearButton] {
            button.isEnabled = controlsEnabled
        }

        rebuildProfileRows(bookmarks: bookmarks, busy: busy)
        updateStatusText(bookmarks: bookmarks, busy: busy)
    }

    private func configure() {
        translatesAutoresizingMaskIntoConstraints = false

        enabledSwitch.controlSize = .small
        enabledSwitch.target = self
        enabledSwitch.action = #selector(preferenceControlChanged)
        enabledSwitch.setAccessibilityLabel(L10n.tr("settings.bookmarks.enabled"))

        includeInDefaultSwitch.controlSize = .small
        includeInDefaultSwitch.target = self
        includeInDefaultSwitch.action = #selector(preferenceControlChanged)
        includeInDefaultSwitch.setAccessibilityLabel(L10n.tr("settings.bookmarks.include_default"))

        for checkbox in [matchTitleCheckbox, matchURLCheckbox, matchFoldersCheckbox] {
            checkbox.target = self
            checkbox.action = #selector(preferenceControlChanged)
        }

        detectButton.target = self
        detectButton.action = #selector(detectClicked)
        chooseDirectoryButton.target = self
        chooseDirectoryButton.action = #selector(chooseDirectoryClicked)
        refreshButton.target = self
        refreshButton.action = #selector(refreshClicked)
        clearButton.target = self
        clearButton.action = #selector(clearClicked)

        statusLabel.font = SettingsStyle.rowSubtitleFont
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.translatesAutoresizingMaskIntoConstraints = false

        let generalSection = SettingsSectionView(
            title: L10n.tr("settings.bookmarks.section.general"),
            rows: [
                SettingsRowView(
                    title: L10n.tr("settings.bookmarks.enabled"),
                    subtitle: L10n.tr("settings.bookmarks.enabled_subtitle"),
                    trailingViews: [enabledSwitch]
                ),
                SettingsRowView(
                    title: L10n.tr("settings.bookmarks.include_default"),
                    subtitle: L10n.tr("settings.default_results.bookmarks_subtitle"),
                    trailingViews: [includeInDefaultSwitch]
                ),
            ]
        )

        let profilesHeader = NSTextField(labelWithString: L10n.tr("settings.bookmarks.section.profiles"))
        profilesHeader.font = SettingsStyle.sectionTitleFont
        profilesHeader.textColor = SettingsStyle.secondaryText
        profilesHeader.translatesAutoresizingMaskIntoConstraints = false
        let profilesHeaderWrap = NSView()
        profilesHeaderWrap.translatesAutoresizingMaskIntoConstraints = false
        profilesHeaderWrap.addSubview(profilesHeader)
        NSLayoutConstraint.activate([
            profilesHeader.leadingAnchor.constraint(equalTo: profilesHeaderWrap.leadingAnchor, constant: 4),
            profilesHeader.trailingAnchor.constraint(equalTo: profilesHeaderWrap.trailingAnchor),
            profilesHeader.topAnchor.constraint(equalTo: profilesHeaderWrap.topAnchor),
            profilesHeader.bottomAnchor.constraint(equalTo: profilesHeaderWrap.bottomAnchor),
        ])

        let profilesSection = NSStackView(views: [profilesHeaderWrap, profilesCard])
        profilesSection.orientation = .vertical
        profilesSection.alignment = .leading
        profilesSection.spacing = 8
        profilesSection.translatesAutoresizingMaskIntoConstraints = false
        profilesHeaderWrap.widthAnchor.constraint(equalTo: profilesSection.widthAnchor).isActive = true
        profilesCard.widthAnchor.constraint(equalTo: profilesSection.widthAnchor).isActive = true

        let matchControls = NSStackView(views: [matchTitleCheckbox, matchURLCheckbox, matchFoldersCheckbox])
        matchControls.orientation = .horizontal
        matchControls.alignment = .centerY
        matchControls.spacing = 12

        let openWithLabel = NSTextField(labelWithString: L10n.tr("settings.bookmarks.default_browser"))
        openWithLabel.font = SettingsStyle.rowSubtitleFont
        openWithLabel.textColor = .secondaryLabelColor

        let matchingSection = SettingsSectionView(
            title: L10n.tr("settings.bookmarks.section.matching"),
            rows: [
                SettingsRowView(
                    title: L10n.tr("settings.bookmarks.keyword"),
                    trailingViews: [SettingsBadgeLabel(text: "bm", tone: .accent, monospaced: true)]
                ),
                SettingsRowView(
                    title: L10n.tr("settings.bookmarks.match_scope"),
                    trailingViews: [matchControls]
                ),
                SettingsRowView(
                    title: L10n.tr("settings.bookmarks.open_with"),
                    trailingViews: [openWithLabel]
                ),
            ]
        )

        let storageSection = SettingsSectionView(
            title: L10n.tr("settings.bookmarks.section.storage"),
            rows: [
                SettingsRowView(
                    title: L10n.tr("settings.bookmarks.clear"),
                    subtitle: L10n.tr("settings.bookmarks.clear_subtitle"),
                    trailingViews: [clearButton]
                ),
            ],
            footer: L10n.tr("settings.bookmarks.note")
        )

        let stack = NSStackView(views: [generalSection, profilesSection, matchingSection, storageSection])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = SettingsStyle.sectionSpacing
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            generalSection.widthAnchor.constraint(equalTo: stack.widthAnchor),
            profilesSection.widthAnchor.constraint(equalTo: stack.widthAnchor),
            matchingSection.widthAnchor.constraint(equalTo: stack.widthAnchor),
            storageSection.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])
    }

    private func rebuildProfileRows(bookmarks: BookmarkStore?, busy: Bool) {
        var rows: [NSView] = []
        if let bookmarks {
            if bookmarks.profiles.isEmpty {
                rows.append(SettingsRowView(
                    title: L10n.tr("settings.bookmarks.profiles"),
                    subtitle: L10n.tr("settings.bookmarks.not_detected")
                ))
            } else {
                for profile in bookmarks.profiles {
                    let count = bookmarks.snapshots[profile.id]?.entries.count
                    let status = count.map { L10n.format("settings.bookmarks.imported_count", $0) }
                        ?? L10n.tr("settings.bookmarks.profile_not_imported")
                    let toggle = NSSwitch()
                    toggle.controlSize = .small
                    toggle.state = profile.selected ? .on : .off
                    toggle.isEnabled = !busy
                    toggle.identifier = NSUserInterfaceItemIdentifier(profile.id)
                    toggle.target = self
                    toggle.action = #selector(profileSwitchChanged(_:))
                    toggle.setAccessibilityLabel(profile.name)

                    let row = SettingsRowView(
                        title: profile.name,
                        subtitle: status,
                        leadingView: SettingsIconBadgeView(symbolName: "person.crop.circle", accented: profile.selected, size: 28, pointSize: 14),
                        trailingViews: [toggle]
                    )
                    row.toolTip = "\(profile.name)\n\(profile.id)"
                    rows.append(row)
                }
            }
        } else {
            rows.append(SettingsRowView(
                title: L10n.tr("settings.bookmarks.profiles"),
                subtitle: L10n.tr("settings.bookmarks.unavailable")
            ))
        }

        rows.append(buildImportFooterRow())
        profilesCard.setRows(rows)
    }

    private func buildImportFooterRow() -> NSView {
        let buttons = NSStackView(views: [detectButton, chooseDirectoryButton, refreshButton])
        buttons.orientation = .horizontal
        buttons.alignment = .centerY
        buttons.spacing = 8

        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        let stack = NSStackView(views: [statusLabel, buttons])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: SettingsStyle.rowHorizontalPadding),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -SettingsStyle.rowHorizontalPadding),
            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: 12),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -12),
            statusLabel.widthAnchor.constraint(lessThanOrEqualTo: stack.widthAnchor),
        ])
        return container
    }

    private func updateStatusText(bookmarks: BookmarkStore?, busy: Bool) {
        guard let bookmarks else {
            statusLabel.stringValue = L10n.tr("settings.bookmarks.unavailable")
            return
        }
        let snapshots = bookmarks.snapshots.values
        if busy {
            statusLabel.stringValue = L10n.tr("settings.bookmarks.reading")
        } else if let date = snapshots.map(\.importedAt).max() {
            let imported = snapshots.reduce(0) { $0 + $1.entries.count }
            let skipped = snapshots.reduce(0) { $0 + $1.skippedCount }
            statusLabel.stringValue = L10n.format(
                "settings.bookmarks.import_status",
                date.formatted(date: .abbreviated, time: .shortened),
                imported,
                skipped
            )
        } else {
            statusLabel.stringValue = L10n.tr("settings.bookmarks.import_help")
        }
        if let warning = bookmarks.warning {
            statusLabel.stringValue += "\n\(warning)"
        }
    }

    @objc private func preferenceControlChanged() {
        var next = currentPreferences
        next.enabled = enabledSwitch.state == .on
        next.includeInDefaultResults = includeInDefaultSwitch.state == .on
        next.matchTitle = matchTitleCheckbox.state == .on
        next.matchURL = matchURLCheckbox.state == .on
        next.matchFolders = matchFoldersCheckbox.state == .on
        currentPreferences = next
        onPreferenceChanged?(next)
    }

    @objc private func profileSwitchChanged(_ sender: NSSwitch) {
        guard let id = sender.identifier?.rawValue else { return }
        onProfileToggled?(id, sender.state == .on)
    }

    @objc private func detectClicked() { onDetectProfiles?() }
    @objc private func chooseDirectoryClicked() { onChooseDirectory?() }
    @objc private func refreshClicked() { onRefreshBookmarks?() }
    @objc private func clearClicked() { onClearBookmarks?() }
}
