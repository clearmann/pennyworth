import AppKit

@MainActor final class MouseScrollSettingsView: NSView {
    private let permissionStatusLabel = NSTextField(wrappingLabelWithString: "")
    private let requestPermissionButton = NSButton(title: L10n.tr("mouse.permission.request"), target: nil, action: nil)
    private let openSettingsButton = NSButton(title: L10n.tr("mouse.permission.open_settings"), target: nil, action: nil)
    private let refreshPermissionButton = NSButton(title: L10n.tr("mouse.permission.refresh"), target: nil, action: nil)

    private let reverseCheckbox = NSButton(checkboxWithTitle: L10n.tr("mouse.reverse_scroll"), target: nil, action: nil)
    private let smoothCheckbox = NSButton(checkboxWithTitle: L10n.tr("mouse.smooth_scroll"), target: nil, action: nil)
    private let speedSlider = NSSlider(
        value: MouseScrollSettings.defaultSpeed,
        minValue: MouseScrollSettings.speedRange.lowerBound,
        maxValue: MouseScrollSettings.speedRange.upperBound,
        target: nil,
        action: nil
    )
    private let speedValueLabel = NSTextField(labelWithString: "1.00x")
    private let smoothnessPopup = NSPopUpButton()
    private let resetButton = NSButton(title: L10n.tr("mouse.reset_defaults"), target: nil, action: nil)

    var onRequestPermission: (() -> Void)?
    var onOpenAccessibilitySettings: (() -> Bool)?
    var onRefreshPermission: (() -> Void)?

    var currentSettings: MouseScrollSettings {
        let smoothnessIndex = max(0, min(ScrollSmoothness.allCases.count - 1, smoothnessPopup.indexOfSelectedItem))
        return MouseScrollSettings(
            reverseScrollDirection: reverseCheckbox.state == .on,
            smoothScrolling: smoothCheckbox.state == .on,
            scrollSpeed: snappedSpeed(speedSlider.doubleValue),
            smoothness: ScrollSmoothness.allCases[smoothnessIndex]
        )
    }

    init() {
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
        reverseCheckbox.state = settings.reverseScrollDirection ? .on : .off
        smoothCheckbox.state = settings.smoothScrolling ? .on : .off
        speedSlider.doubleValue = snappedSpeed(settings.scrollSpeed)
        updateSpeedLabel()
        let smoothnessIndex = ScrollSmoothness.allCases.firstIndex(of: settings.smoothness) ?? 1
        smoothnessPopup.selectItem(at: smoothnessIndex)
        updateControlStates()
        updatePermissionStatus(status, isTrusted: isTrusted)
    }

    func updatePermissionStatus(_ status: MouseScrollController.RuntimeStatus, isTrusted: Bool) {
        switch status {
        case .active:
            permissionStatusLabel.stringValue = L10n.tr("mouse.permission.status.active")
        case .awaitingAccessibilityPermission:
            permissionStatusLabel.stringValue = L10n.tr("mouse.permission.status.awaiting")
        case .tapFailed:
            permissionStatusLabel.stringValue = L10n.tr("mouse.permission.status.tap_failed")
        case .inactive:
            permissionStatusLabel.stringValue = isTrusted
                ? L10n.tr("mouse.permission.status.granted")
                : L10n.tr("mouse.permission.status.not_granted")
        }
        requestPermissionButton.isHidden = isTrusted
    }

    private func configure() {
        translatesAutoresizingMaskIntoConstraints = false

        permissionStatusLabel.font = .systemFont(ofSize: 12)
        permissionStatusLabel.textColor = .secondaryLabelColor

        requestPermissionButton.target = self
        requestPermissionButton.action = #selector(requestPermissionClicked)
        openSettingsButton.target = self
        openSettingsButton.action = #selector(openSettingsClicked)
        refreshPermissionButton.target = self
        refreshPermissionButton.action = #selector(refreshPermissionClicked)

        reverseCheckbox.setAccessibilityLabel(L10n.tr("mouse.reverse_scroll_accessibility"))
        smoothCheckbox.setAccessibilityLabel(L10n.tr("mouse.smooth_scroll_accessibility"))
        smoothCheckbox.target = self
        smoothCheckbox.action = #selector(smoothScrollingChanged)

        speedSlider.numberOfTickMarks = 11
        speedSlider.allowsTickMarkValuesOnly = true
        speedSlider.isContinuous = true
        speedSlider.target = self
        speedSlider.action = #selector(speedChanged)
        speedSlider.setAccessibilityLabel(L10n.tr("mouse.scroll_speed"))
        speedSlider.widthAnchor.constraint(equalToConstant: 240).isActive = true

        speedValueLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        speedValueLabel.textColor = .secondaryLabelColor
        speedValueLabel.widthAnchor.constraint(equalToConstant: 46).isActive = true

        smoothnessPopup.addItems(withTitles: ScrollSmoothness.allCases.map(\.title))
        smoothnessPopup.setAccessibilityLabel(L10n.tr("mouse.smoothness"))
        smoothnessPopup.widthAnchor.constraint(equalToConstant: 180).isActive = true

        resetButton.target = self
        resetButton.action = #selector(resetToDefaults)

        let permissionButtons = NSStackView(views: [requestPermissionButton, openSettingsButton, refreshPermissionButton])
        permissionButtons.spacing = 8

        let speedControl = NSStackView(views: [speedSlider, speedValueLabel])
        speedControl.alignment = .centerY
        speedControl.spacing = 10

        let stack = NSStackView(views: [
            permissionStatusLabel,
            permissionButtons,
            reverseCheckbox,
            smoothCheckbox,
            row(L10n.tr("mouse.scroll_speed"), speedControl),
            row(L10n.tr("mouse.smoothness"), smoothnessPopup),
            resetButton,
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            permissionStatusLabel.widthAnchor.constraint(lessThanOrEqualTo: stack.widthAnchor),
        ])

        updateSpeedLabel()
        updateControlStates()
    }

    private func row(_ title: String, _ control: NSView) -> NSView {
        let label = NSTextField(labelWithString: title)
        label.widthAnchor.constraint(equalToConstant: 116).isActive = true
        let stack = NSStackView(views: [label, control])
        stack.alignment = .centerY
        stack.spacing = 12
        return stack
    }

    private func snappedSpeed(_ value: Double) -> Double {
        let clamped = min(max(value, MouseScrollSettings.speedRange.lowerBound), MouseScrollSettings.speedRange.upperBound)
        return (clamped * 4.0).rounded() / 4.0
    }

    private func updateSpeedLabel() {
        speedValueLabel.stringValue = String(format: "%.2fx", snappedSpeed(speedSlider.doubleValue))
    }

    private func updateControlStates() {
        smoothnessPopup.isEnabled = smoothCheckbox.state == .on
    }

    @objc private func smoothScrollingChanged() {
        updateControlStates()
    }

    @objc private func speedChanged() {
        speedSlider.doubleValue = snappedSpeed(speedSlider.doubleValue)
        updateSpeedLabel()
    }

    @objc private func resetToDefaults() {
        let defaults = MouseScrollSettings.defaults
        reverseCheckbox.state = defaults.reverseScrollDirection ? .on : .off
        smoothCheckbox.state = defaults.smoothScrolling ? .on : .off
        speedSlider.doubleValue = defaults.scrollSpeed
        updateSpeedLabel()
        smoothnessPopup.selectItem(at: ScrollSmoothness.allCases.firstIndex(of: defaults.smoothness) ?? 1)
        updateControlStates()
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
