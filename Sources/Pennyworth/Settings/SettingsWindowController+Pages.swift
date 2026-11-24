import AppKit

// MARK: - Page Builders

extension SettingsWindowController {

    func buildPages() {
        buildGeneralPage()
        buildAppShortcutsPage()
        buildDefaultResultsPage()
        buildFileSearchPage()
        buildWebSearchPage()
        buildBookmarksPage()
        buildCalculatorPage()
        buildScreenshotsPage()
        buildMousePage()
        buildImageUploadPage()
    }

    private func buildGeneralPage() {
        let appearanceSection = SettingsSectionView(
            title: L10n.tr("settings.general.section.appearance"),
            rows: [
                SettingsRowView(
                    title: L10n.tr("settings.language"),
                    subtitle: L10n.tr("settings.general.language_subtitle"),
                    trailingViews: [languagePopup]
                ),
            ]
        )
        let hotkeysSection = SettingsSectionView(
            title: L10n.tr("settings.general.section.hotkeys"),
            rows: [
                SettingsRowView(
                    title: L10n.tr("settings.hotkey"),
                    subtitle: L10n.tr("settings.general.hotkey_subtitle"),
                    trailingViews: [hotKeyRecorder]
                ),
                SettingsRowView(
                    title: L10n.tr("settings.clipboard_hotkey"),
                    subtitle: L10n.tr("settings.general.clipboard_subtitle"),
                    trailingViews: [clipboardHotKeyRecorder]
                ),
            ],
            footer: L10n.tr("settings.general.right_command_note")
        )
        let clearUsageButton = SettingsStyle.makeButton(
            title: L10n.tr("settings.clear_usage"),
            primary: false,
            target: self,
            action: #selector(clearHistory)
        )
        let usageSection = SettingsSectionView(
            title: L10n.tr("settings.general.section.usage"),
            rows: [
                SettingsRowView(
                    title: L10n.tr("settings.remember_usage"),
                    subtitle: L10n.tr("settings.general.remember_subtitle"),
                    trailingViews: [rememberSwitch]
                ),
                SettingsRowView(
                    title: L10n.tr("settings.general.clear_usage_title"),
                    subtitle: L10n.tr("settings.general.clear_usage_subtitle"),
                    trailingViews: [clearUsageButton]
                ),
            ]
        )
        addPage(
            L10n.tr("settings.page.general"),
            description: L10n.tr("settings.general.description"),
            sections: [appearanceSection, hotkeysSection, usageSection]
        )
    }

    private func buildAppShortcutsPage() {
        let addButton = SettingsStyle.makeButton(
            title: L10n.tr("app_shortcuts.add"),
            symbolName: "plus",
            primary: true,
            target: appShortcutsSettings,
            action: #selector(AppShortcutsSettingsView.presentAddSheet)
        )
        let note = makeFootnote(L10n.tr("settings.app_shortcuts.note"))
        addPage(
            L10n.tr("settings.page.app_shortcuts"),
            description: L10n.tr("settings.app_shortcuts.description"),
            headerAccessory: addButton,
            sections: [appShortcutsSettings, note]
        )
    }

    private func buildDefaultResultsPage() {
        let bookmarkLink = SettingsStyle.makeButton(
            title: L10n.tr("settings.bookmarks.configure"),
            primary: false,
            target: self,
            action: #selector(openBookmarks)
        )
        bookmarkLink.controlSize = .small

        let sourcesSection = SettingsSectionView(
            title: L10n.tr("settings.default_results.section.sources"),
            rows: [
                SettingsRowView(
                    title: L10n.tr("settings.default_results.apps_title"),
                    subtitle: L10n.tr("settings.default_results.note"),
                    trailingViews: [SettingsBadgeLabel(text: L10n.tr("common.always_on"), tone: .success)]
                ),
                SettingsRowView(
                    title: L10n.tr("settings.default_results.bookmarks_title"),
                    subtitle: L10n.tr("settings.default_results.bookmarks_subtitle"),
                    trailingViews: [bookmarkLink, defaultBookmarksSwitch]
                ),
            ],
            footer: L10n.tr("settings.default_results.bookmarks_note")
        )
        let fallbackSection = SettingsSectionView(
            title: L10n.tr("settings.default_results.section.fallback"),
            rows: [
                SettingsRowView(
                    title: L10n.tr("settings.web_fallback"),
                    subtitle: L10n.tr("settings.default_results.fallback_subtitle"),
                    trailingViews: [fallbackPopup]
                ),
            ]
        )
        addPage(
            L10n.tr("settings.page.default_results"),
            description: L10n.tr("settings.default_results.description"),
            sections: [sourcesSection, fallbackSection]
        )
    }

    private func buildFileSearchPage() {
        let addDirButton = SettingsStyle.makeButton(
            title: L10n.tr("settings.add_directory"),
            symbolName: "plus",
            primary: true,
            target: self,
            action: #selector(addDirectory)
        )
        let dirHeader = makeSectionLabel(L10n.tr("settings.file_search.section.directories"))
        let dirNote = makeFootnote(L10n.tr("settings.file_search.spotlight_note"))
        let dirGroup = NSStackView(views: [dirHeader, fileSearchSettings, dirNote])
        dirGroup.orientation = .vertical
        dirGroup.alignment = .leading
        dirGroup.spacing = 8
        dirGroup.translatesAutoresizingMaskIntoConstraints = false
        fileSearchSettings.widthAnchor.constraint(equalTo: dirGroup.widthAnchor).isActive = true
        dirNote.widthAnchor.constraint(equalTo: dirGroup.widthAnchor).isActive = true

        let commandsSection = SettingsSectionView(
            title: L10n.tr("settings.file_search.section.commands"),
            rows: [
                SettingsRowView(
                    title: L10n.tr("settings.file_search.cmd_open_title"),
                    subtitle: L10n.tr("settings.file_search.cmd_open_subtitle"),
                    trailingViews: [SettingsBadgeLabel(text: "open", tone: .neutral, monospaced: true, minWidth: 52)]
                ),
                SettingsRowView(
                    title: L10n.tr("settings.file_search.cmd_find_title"),
                    subtitle: L10n.tr("settings.file_search.cmd_find_subtitle"),
                    trailingViews: [SettingsBadgeLabel(text: "find", tone: .neutral, monospaced: true, minWidth: 52)]
                ),
            ]
        )
        addPage(
            L10n.tr("settings.page.file_search"),
            description: L10n.tr("settings.file_search.description"),
            headerAccessory: addDirButton,
            sections: [dirGroup, commandsSection]
        )
    }

    private func buildWebSearchPage() {
        let addSearchButton = SettingsStyle.makeButton(
            title: L10n.tr("web_search.add"),
            symbolName: "plus",
            primary: true,
            target: webSearchSettings,
            action: #selector(WebSearchSettingsView.presentAddSheet)
        )
        let defaultEngineSection = SettingsSectionView(
            title: L10n.tr("web_search.section.default_engine"),
            rows: [
                SettingsRowView(
                    title: L10n.tr("settings.search_engine"),
                    subtitle: L10n.tr("web_search.engine_subtitle"),
                    trailingViews: [enginePopup]
                ),
            ]
        )
        let keywordsHeader = makeSectionLabel(L10n.tr("web_search.section.keywords"))
        let keywordsNote = makeFootnote(L10n.tr("settings.web_search.note"))
        let keywordsGroup = NSStackView(views: [keywordsHeader, webSearchSettings, keywordsNote])
        keywordsGroup.orientation = .vertical
        keywordsGroup.alignment = .leading
        keywordsGroup.spacing = 8
        keywordsGroup.translatesAutoresizingMaskIntoConstraints = false
        webSearchSettings.widthAnchor.constraint(equalTo: keywordsGroup.widthAnchor).isActive = true
        keywordsNote.widthAnchor.constraint(equalTo: keywordsGroup.widthAnchor).isActive = true

        addPage(
            L10n.tr("settings.page.web_search"),
            description: L10n.tr("settings.web_search.description"),
            headerAccessory: addSearchButton,
            sections: [defaultEngineSection, keywordsGroup]
        )
    }

    private func buildBookmarksPage() {
        addPage(
            L10n.tr("settings.page.bookmarks"),
            description: L10n.tr("settings.bookmarks.description"),
            sections: [bookmarksSettings]
        )
    }

    private func buildCalculatorPage() {
        let usageSection = SettingsSectionView(
            title: L10n.tr("settings.calculator.section.usage"),
            rows: [
                SettingsRowView(
                    title: L10n.tr("settings.calculator.direct_title"),
                    subtitle: L10n.tr("settings.calculator.syntax_note"),
                    trailingViews: [SettingsBadgeLabel(text: "23 * 17", tone: .neutral, monospaced: true)]
                ),
                SettingsRowView(
                    title: L10n.tr("settings.calculator.prefix_title"),
                    subtitle: L10n.tr("settings.calculator.prefix_subtitle"),
                    trailingViews: [SettingsBadgeLabel(text: "= (12 + 8) / 4", tone: .accent, monospaced: true)]
                ),
                SettingsRowView(
                    title: L10n.tr("settings.calculator.copy_title"),
                    subtitle: L10n.tr("settings.calculator.copy_subtitle"),
                    trailingViews: [SettingsBadgeLabel(text: L10n.tr("launcher.keycap.copy"), tone: .neutral, monospaced: true)]
                ),
            ]
        )
        addPage(
            L10n.tr("settings.page.calculator"),
            description: L10n.tr("settings.calculator.description"),
            sections: [usageSection]
        )
    }

    private func buildScreenshotsPage() {
        let hotkeySection = SettingsSectionView(
            title: L10n.tr("settings.screenshots.section.hotkey"),
            rows: [
                SettingsRowView(
                    title: L10n.tr("settings.screenshot_hotkey"),
                    subtitle: L10n.tr("settings.screenshots.hotkey_subtitle"),
                    trailingViews: [screenshotHotKeyRecorder]
                ),
            ]
        )
        let commandsSection = SettingsSectionView(
            title: L10n.tr("settings.screenshots.section.commands"),
            rows: [
                SettingsRowView(
                    title: L10n.tr("launcher.screenshot.capture"),
                    subtitle: L10n.tr("launcher.screenshot.capture_subtitle"),
                    trailingViews: [
                        SettingsBadgeLabel(text: "shot", tone: .neutral, monospaced: true),
                        SettingsBadgeLabel(text: "截图", tone: .neutral),
                    ]
                ),
                SettingsRowView(
                    title: L10n.tr("launcher.screenshot.pin_clipboard"),
                    subtitle: L10n.tr("launcher.screenshot.pin_clipboard_subtitle"),
                    trailingViews: [
                        SettingsBadgeLabel(text: "pin", tone: .neutral, monospaced: true),
                        SettingsBadgeLabel(text: "贴图", tone: .neutral),
                    ]
                ),
            ]
        )
        addPage(
            L10n.tr("settings.page.screenshots"),
            description: L10n.tr("settings.screenshots.description"),
            sections: [hotkeySection, commandsSection]
        )
    }

    private func buildMousePage() {
        let resetButton = SettingsStyle.makeButton(
            title: L10n.tr("mouse.reset_defaults"),
            primary: false,
            target: mouseScrollSettings,
            action: #selector(MouseScrollSettingsView.resetToDefaults)
        )
        addPage(
            L10n.tr("settings.page.mouse"),
            description: L10n.tr("settings.mouse.description"),
            headerAccessory: resetButton,
            sections: [mouseScrollSettings]
        )
    }

    private func buildImageUploadPage() {
        addPage(
            L10n.tr("settings.page.image_upload"),
            description: L10n.tr("settings.image_upload.description"),
            sections: [imageUploadSettings]
        )
    }

    private func addPage(
        _ title: String,
        description: String,
        headerAccessory: NSView? = nil,
        sections: [NSView]
    ) {
        let heading = NSTextField(labelWithString: title)
        heading.font = SettingsStyle.pageTitleFont
        heading.textColor = .labelColor

        let subtitle = NSTextField(wrappingLabelWithString: description)
        subtitle.font = SettingsStyle.pageSubtitleFont
        subtitle.textColor = SettingsStyle.secondaryText
        subtitle.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let titleStack = NSStackView(views: [heading, subtitle])
        titleStack.orientation = .vertical
        titleStack.alignment = .leading
        titleStack.spacing = 4
        titleStack.translatesAutoresizingMaskIntoConstraints = false
        titleStack.setContentHuggingPriority(.defaultLow, for: .horizontal)
        titleStack.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let headerView = NSView()
        headerView.translatesAutoresizingMaskIntoConstraints = false
        headerView.addSubview(titleStack)
        var headerConstraints: [NSLayoutConstraint] = [
            titleStack.leadingAnchor.constraint(equalTo: headerView.leadingAnchor),
            titleStack.topAnchor.constraint(equalTo: headerView.topAnchor),
            titleStack.bottomAnchor.constraint(equalTo: headerView.bottomAnchor),
        ]
        if let accessory = headerAccessory {
            accessory.translatesAutoresizingMaskIntoConstraints = false
            accessory.setContentHuggingPriority(.required, for: .horizontal)
            accessory.setContentCompressionResistancePriority(.required, for: .horizontal)
            headerView.addSubview(accessory)
            headerConstraints.append(contentsOf: [
                accessory.trailingAnchor.constraint(equalTo: headerView.trailingAnchor),
                accessory.centerYAnchor.constraint(equalTo: heading.centerYAnchor),
                titleStack.trailingAnchor.constraint(lessThanOrEqualTo: accessory.leadingAnchor, constant: -16),
            ])
        } else {
            headerConstraints.append(titleStack.trailingAnchor.constraint(equalTo: headerView.trailingAnchor))
        }
        NSLayoutConstraint.activate(headerConstraints)

        let stack = NSStackView(views: [headerView] + sections)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = SettingsStyle.sectionSpacing
        stack.translatesAutoresizingMaskIntoConstraints = false
        pageHost.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: pageHost.leadingAnchor, constant: SettingsStyle.contentHorizontalPadding),
            stack.trailingAnchor.constraint(equalTo: pageHost.trailingAnchor, constant: -SettingsStyle.contentHorizontalPadding),
            stack.topAnchor.constraint(equalTo: pageHost.topAnchor, constant: SettingsStyle.contentTopPadding),
            headerView.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])
        for section in sections {
            section.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
        pages[title] = stack
    }

    private func makeSectionLabel(_ text: String) -> NSView {
        let label = NSTextField(labelWithString: text)
        label.font = SettingsStyle.sectionTitleFont
        label.textColor = SettingsStyle.secondaryText
        label.translatesAutoresizingMaskIntoConstraints = false
        let wrapper = NSView()
        wrapper.translatesAutoresizingMaskIntoConstraints = false
        wrapper.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor, constant: 4),
            label.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor),
            label.topAnchor.constraint(equalTo: wrapper.topAnchor),
            label.bottomAnchor.constraint(equalTo: wrapper.bottomAnchor),
        ])
        return wrapper
    }

    private func makeFootnote(_ text: String) -> NSView {
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = SettingsStyle.footnoteFont
        label.textColor = SettingsStyle.secondaryText
        label.translatesAutoresizingMaskIntoConstraints = false
        let wrapper = NSView()
        wrapper.translatesAutoresizingMaskIntoConstraints = false
        wrapper.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor, constant: 4),
            label.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor, constant: -4),
            label.topAnchor.constraint(equalTo: wrapper.topAnchor),
            label.bottomAnchor.constraint(equalTo: wrapper.bottomAnchor),
        ])
        return wrapper
    }
}
