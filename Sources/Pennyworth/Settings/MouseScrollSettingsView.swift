import AppKit

/// Card-based mouse scroll enhancement settings with live permission status and instant apply.
@MainActor final class MouseScrollSettingsView: NSView {
    private let permissionBadge = SettingsBadgeLabel(text: "", tone: .neutral)
    private let permissionStatusLabel = NSTextField(wrappingLabelWithString: "")
    private let requestPermissionButton: NSButton
    private let openSettingsButton: NSButton
    private let refreshPermissionButton: NSButton

    private let reverseSwitch = NSSwitch()
    private let smoothSwitch = NSSwitch()
    private let speedSlider = NSSlider(
        value: MouseScrollSettings.defaultSpeed,
        minValue: MouseScrollSettings.speedRange.lowerBound,
        maxValue: MouseScrollSettings.speedRange.upperBound,
        target: nil,
        action: nil
    )
    private let speedValueBadge = SettingsBadgeLabel(text: "1.00x", tone: .neutral, monospaced: true, minWidth: 54)
    private let smoothnessControl = NSSegmentedControl()

    private var appliedSettings: MouseScrollSettings = .defaults

    var onRequestPermission: (() -> Void)?
    var onOpenAccessibilitySettings: (() -> Bool)?
    var onRefreshPermission: (() -> Void)?
    var onCommitSettings: ((MouseScrollSettings) -> Result<Void, Error>)?

    var currentSettings: MouseScrollSettings {
        let index = max(0, min(ScrollSmoothness.allCases.count - 1, smoothnessControl.selectedSegment))
        return MouseScrollSettings(
            reverseScrollDirection: reverseSwitch.state == .on,
            smoothScrolling: smoothSwitch.state == .on,
            scrollSpeed: snappedSpeed(speedSlider.doubleValue),
            smoothness: ScrollSmoothness.allCases[index]
        )
    }

    init() {
        requestPermissionButton = SettingsStyle.makeButton(
            title: L10n.tr("mouse.permission.request"),
            primary: true,
            target: nil,
            action: nil
        )
        openSettingsButton = SettingsStyle.makeButton(
            title: L10n.tr("mouse.permission.open_settings"),
            primary: false,
            target: nil,
            action: nil
        )
        refreshPermissionButton = SettingsStyle.makeButton(
            title: L10n.tr("mouse.permission.refresh"),
            primary: false,
            target: nil,
            action: nil
        )
        super.init(frame: .zero)
        configure()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func reload(
        _ settings: MouseScrollSettings,
        status: MouseScrollController.RuntimeStatus,
        isTrusted: Bool
    ) {
        appliedSettings = settings
        applyUIValues(settings)
        updatePermissionStatus(status, isTrusted: isTrusted)
    }

    func updatePermissionStatus(_ status: MouseScrollController.RuntimeStatus, isTrusted: Bool) {
        switch status {
        case .active:
            permissionBadge.update(text: L10n.tr("common.enabled"), tone: .success)
            permissionStatusLabel.stringValue = L10n.tr("mouse.permission.status.active")
        case .awaitingAccessibilityPermission:
            permissionBadge.update(text: "!", tone: .warning)
            permissionStatusLabel.stringValue = L10n.tr("mouse.permission.status.awaiting")
        case .tapFailed:
            permissionBadge.update(text: "!", tone: .error)
            permissionStatusLabel.stringValue = L10n.tr("mouse.permission.status.tap_failed")
        case .inactive:
            if isTrusted {
                permissionBadge.update(text: "✓", tone: .success)
                permissionStatusLabel.stringValue = L10n.tr("mouse.permission.status.granted")
            } else {
                permissionBadge.update(text: "!", tone: .warning)
                permissionStatusLabel.stringValue = L10n.tr("mouse.permission.status.not_granted")
            }
        }
        requestPermissionButton.isHidden = isTrusted
    }

    @objc func resetToDefaults() {
        applyUIValues(.defaults)
        commitCurrentSettings()
    }

    private func configure() {
        translatesAutoresizingMaskIntoConstraints = false

        requestPermissionButton.target = self
        requestPermissionButton.action = #selector(requestPermissionClicked)
        openSettingsButton.target = self
        openSettingsButton.action = #selector(openSettingsClicked)
        refreshPermissionButton.target = self
        refreshPermissionButton.action = #selector(refreshPermissionClicked)

        permissionStatusLabel.font = SettingsStyle.rowSubtitleFont
        permissionStatusLabel.textColor = SettingsStyle.secondaryText
        permissionStatusLabel.translatesAutoresizingMaskIntoConstraints = false

        let permissionStatusRow = buildPermissionRow()
        let permissionSection = SettingsSectionView(
            title: L10n.tr("mouse.section.permission"),
            rows: [permissionStatusRow]
        )

        reverseSwitch.controlSize = .small
        reverseSwitch.target = self
        reverseSwitch.action = #selector(settingsControlChanged)
        reverseSwitch.setAccessibilityLabel(L10n.tr("mouse.reverse_scroll_accessibility"))

        smoothSwitch.controlSize = .small
        smoothSwitch.target = self
        smoothSwitch.action = #selector(smoothScrollingChanged)
        smoothSwitch.setAccessibilityLabel(L10n.tr("mouse.smooth_scroll_accessibility"))

        speedSlider.numberOfTickMarks = 11
        speedSlider.allowsTickMarkValuesOnly = true
        speedSlider.isContinuous = true
        speedSlider.target = self
        speedSlider.action = #selector(speedChanged)
        speedSlider.setAccessibilityLabel(L10n.tr("mouse.scroll_speed"))
        speedSlider.widthAnchor.constraint(equalToConstant: 180).isActive = true

        smoothnessControl.segmentCount = ScrollSmoothness.allCases.count
        smoothnessControl.trackingMode = .selectOne
        smoothnessControl.segmentStyle = .rounded
        for (index, preset) in ScrollSmoothness.allCases.enumerated() {
            smoothnessControl.setLabel(preset.title, forSegment: index)
        }
        smoothnessControl.selectedSegment = 1
        smoothnessControl.target = self
        smoothnessControl.action = #selector(settingsControlChanged)
        smoothnessControl.setAccessibilityLabel(L10n.tr("mouse.smoothness"))

        let speedControl = NSStackView(views: [speedSlider, speedValueBadge])
        speedControl.orientation = .horizontal
        speedControl.alignment = .centerY
        speedControl.spacing = 10

        let behaviorSection = SettingsSectionView(
            title: L10n.tr("mouse.section.behavior"),
            rows: [
                SettingsRowView(
                    title: L10n.tr("mouse.reverse_scroll"),
                    subtitle: L10n.tr("mouse.reverse_subtitle"),
                    trailingViews: [reverseSwitch]
                ),
                SettingsRowView(
                    title: L10n.tr("mouse.smooth_scroll"),
                    subtitle: L10n.tr("mouse.smooth_subtitle"),
                    trailingViews: [smoothSwitch]
                ),
                SettingsRowView(
                    title: L10n.tr("mouse.scroll_speed"),
                    subtitle: L10n.tr("mouse.speed_subtitle"),
                    trailingViews: [speedControl]
                ),
                SettingsRowView(
                    title: L10n.tr("mouse.smoothness"),
                    subtitle: L10n.tr("mouse.smoothness_subtitle"),
                    trailingViews: [smoothnessControl]
                ),
            ],
            footer: L10n.tr("settings.mouse.note")
        )

        let stack = NSStackView(views: [permissionSection, behaviorSection])
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
            permissionSection.widthAnchor.constraint(equalTo: stack.widthAnchor),
            behaviorSection.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])

        updateSpeedBadge()
        updateControlStates()
    }

    private func buildPermissionRow() -> NSView {
        let topRow = NSStackView(views: [permissionBadge, permissionStatusLabel])
        topRow.orientation = .horizontal
        topRow.alignment = .centerY
        topRow.spacing = 8

        let buttons = NSStackView(views: [requestPermissionButton, openSettingsButton, refreshPermissionButton])
        buttons.orientation = .horizontal
        buttons.alignment = .centerY
        buttons.spacing = 8

        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        let stack = NSStackView(views: [topRow, buttons])
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
            topRow.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])
        return container
    }

    private func applyUIValues(_ settings: MouseScrollSettings) {
        reverseSwitch.state = settings.reverseScrollDirection ? .on : .off
        smoothSwitch.state = settings.smoothScrolling ? .on : .off
        speedSlider.doubleValue = snappedSpeed(settings.scrollSpeed)
        updateSpeedBadge()
        smoothnessControl.selectedSegment = ScrollSmoothness.allCases.firstIndex(of: settings.smoothness) ?? 1
        updateControlStates()
    }

    private func commitCurrentSettings() {
        let next = currentSettings
        let result = onCommitSettings?(next) ?? .success(())
        switch result {
        case .success:
            appliedSettings = next
        case .failure:
            applyUIValues(appliedSettings)
        }
    }

    private func snappedSpeed(_ value: Double) -> Double {
        let clamped = min(max(value, MouseScrollSettings.speedRange.lowerBound), MouseScrollSettings.speedRange.upperBound)
        return (clamped * 4.0).rounded() / 4.0
    }

    private func updateSpeedBadge() {
        speedValueBadge.update(text: String(format: "%.2fx", snappedSpeed(speedSlider.doubleValue)))
    }

    private func updateControlStates() {
        smoothnessControl.isEnabled = smoothSwitch.state == .on
    }

    @objc private func smoothScrollingChanged() {
        updateControlStates()
        commitCurrentSettings()
    }

    @objc private func speedChanged() {
        speedSlider.doubleValue = snappedSpeed(speedSlider.doubleValue)
        updateSpeedBadge()
        commitCurrentSettings()
    }

    @objc private func settingsControlChanged() {
        commitCurrentSettings()
    }

    @objc private func requestPermissionClicked() {
        onRequestPermission?()
    }

    @objc private func openSettingsClicked() {
        _ = onOpenAccessibilitySettings?()
    }

    @objc private func refreshPermissionClicked() {
        onRefreshPermission?()
    }
}
