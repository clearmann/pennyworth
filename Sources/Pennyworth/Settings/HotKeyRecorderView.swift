import AppKit
import Carbon

@MainActor final class HotKeyRecorderView: NSView {
    private(set) var binding: HotKeyPreset?
    private var originalBinding: HotKeyPreset?
    private(set) var isRecording = false
    private var validationErrorText: String?
    private var isHovered = false
    private var tracking: NSTrackingArea?

    let allowsClearing: Bool
    private let compact: Bool

    var onChange: ((HotKeyPreset?) -> Void)?
    var onRecordingStateChanged: ((Bool) -> Void)?

    private let label = NSTextField(labelWithString: "")
    private let clearButton: NSButton
    private var labelTrailingToEdge: NSLayoutConstraint!
    private var labelTrailingToClear: NSLayoutConstraint!

    init(binding: HotKeyPreset?, allowsClearing: Bool = true, compact: Bool = false) {
        self.binding = binding
        self.allowsClearing = allowsClearing
        self.compact = compact
        clearButton = NSButton(frame: .zero)
        super.init(frame: .zero)

        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false
        layer?.cornerRadius = SettingsStyle.controlCornerRadius
        layer?.borderWidth = 1

        label.font = SettingsStyle.keycapFont
        label.alignment = .center
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false
        label.setContentHuggingPriority(.defaultLow, for: .horizontal)
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        clearButton.title = ""
        clearButton.isBordered = false
        let iconConfig = NSImage.SymbolConfiguration(pointSize: 11, weight: .medium)
        clearButton.image = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: L10n.tr("hotkey.clear_accessibility"))?
            .withSymbolConfiguration(iconConfig)
        clearButton.contentTintColor = .tertiaryLabelColor
        clearButton.target = self
        clearButton.action = #selector(clearButtonClicked)
        clearButton.toolTip = L10n.tr("hotkey.clear_accessibility")
        clearButton.setAccessibilityLabel(L10n.tr("hotkey.clear_accessibility"))
        clearButton.translatesAutoresizingMaskIntoConstraints = false
        clearButton.setContentHuggingPriority(.required, for: .horizontal)
        clearButton.setContentCompressionResistancePriority(.required, for: .horizontal)

        addSubview(label)
        addSubview(clearButton)

        labelTrailingToEdge = label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10)
        labelTrailingToClear = label.trailingAnchor.constraint(equalTo: clearButton.leadingAnchor, constant: -4)

        let minWidth: CGFloat = compact ? 116 : 158
        let height: CGFloat = compact ? 28 : 30
        NSLayoutConstraint.activate([
            widthAnchor.constraint(greaterThanOrEqualToConstant: minWidth),
            heightAnchor.constraint(equalToConstant: height),
            clearButton.widthAnchor.constraint(equalToConstant: 16),
            clearButton.heightAnchor.constraint(equalToConstant: 16),
            clearButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -7),
            clearButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])

        setAccessibilityRole(.button)
        setAccessibilityLabel(L10n.tr("hotkey.recorder_accessibility"))
        updateDisplay()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var acceptsFirstResponder: Bool { true }

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

    override func resignFirstResponder() -> Bool {
        let resigned = super.resignFirstResponder()
        if resigned, isRecording {
            binding = originalBinding
            finishRecording()
        }
        return resigned
    }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        beginRecording()
        window?.makeFirstResponder(self)
    }

    var isEnabled = true {
        didSet {
            if !isEnabled, isRecording {
                binding = originalBinding
                finishRecording()
            }
            alphaValue = isEnabled ? 1.0 : 0.45
            updateDisplay()
        }
    }

    override func keyDown(with event: NSEvent) {
        guard isEnabled else { super.keyDown(with: event); return }
        _ = processKey(keyCode: UInt32(event.keyCode), modifiers: Self.carbonModifiers(event.modifierFlags))
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard isEnabled, isRecording else { return super.performKeyEquivalent(with: event) }
        return processKey(keyCode: UInt32(event.keyCode), modifiers: Self.carbonModifiers(event.modifierFlags))
    }

    func setBinding(_ binding: HotKeyPreset?) {
        if isRecording {
            finishRecording()
        }
        self.binding = binding
        validationErrorText = nil
        updateDisplay()
    }

    func beginRecording() {
        guard isEnabled else { return }
        originalBinding = binding
        validationErrorText = nil
        let wasRecording = isRecording
        isRecording = true
        updateDisplay()
        if !wasRecording {
            onRecordingStateChanged?(true)
        }
    }

    @discardableResult
    func processKey(keyCode: UInt32, modifiers: UInt32) -> Bool {
        if keyCode == UInt32(kVK_Escape) {
            binding = originalBinding
            finishRecording()
            return true
        }
        if keyCode == UInt32(kVK_Delete) || keyCode == UInt32(kVK_ForwardDelete) {
            guard allowsClearing else {
                validationErrorText = L10n.tr("hotkey.modifier_required")
                updateDisplay()
                return false
            }
            binding = nil
            finishRecording()
            onChange?(nil)
            return true
        }
        guard modifiers != 0 || HotKeyPreset.supportsWithoutModifier(keyCode) else {
            validationErrorText = L10n.tr("hotkey.modifier_required")
            updateDisplay()
            return false
        }
        let updated = HotKeyPreset.custom(keyCode: keyCode, modifiers: modifiers)
        binding = updated
        finishRecording()
        onChange?(updated)
        return true
    }

    func clearBinding() {
        binding = nil
        finishRecording()
        onChange?(nil)
    }

    @objc private func clearButtonClicked() {
        guard isEnabled, allowsClearing else { return }
        clearBinding()
    }

    private func finishRecording() {
        let wasRecording = isRecording
        isRecording = false
        validationErrorText = nil
        updateDisplay()
        if wasRecording {
            onRecordingStateChanged?(false)
        }
    }

    private func updateDisplay() {
        let showClearButton: Bool
        if isRecording {
            label.stringValue = validationErrorText ?? (compact ? L10n.tr("hotkey.recording_short") : L10n.tr("hotkey.press_or_cancel"))
            label.font = .systemFont(ofSize: 12, weight: .medium)
            showClearButton = false
            toolTip = L10n.tr("hotkey.press_or_cancel")
        } else if let binding {
            label.stringValue = binding.title
            label.font = SettingsStyle.keycapFont
            showClearButton = allowsClearing && isEnabled
            toolTip = L10n.tr("hotkey.click_to_record")
        } else {
            label.stringValue = compact ? L10n.tr("hotkey.click_short") : L10n.tr("hotkey.click_to_record")
            label.font = .systemFont(ofSize: 12, weight: .regular)
            showClearButton = false
            toolTip = L10n.tr("hotkey.click_to_record")
        }
        clearButton.isHidden = !showClearButton
        labelTrailingToEdge.isActive = !showClearButton
        labelTrailingToClear.isActive = showClearButton
        applyAppearanceColors()
    }

    private func applyAppearanceColors() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            if isRecording {
                if validationErrorText != nil {
                    layer?.backgroundColor = SettingsStyle.statusBackground(for: .error).cgColor
                    layer?.borderColor = NSColor.systemRed.cgColor
                    layer?.borderWidth = 1.5
                    label.textColor = .systemRed
                } else {
                    layer?.backgroundColor = SettingsStyle.keycapRecordingFill.cgColor
                    layer?.borderColor = PennyworthTheme.accentPrimary.cgColor
                    layer?.borderWidth = 1.5
                    label.textColor = PennyworthTheme.accentPrimary
                }
            } else if binding != nil {
                layer?.backgroundColor = SettingsStyle.keycapFill.cgColor
                layer?.borderColor = (isHovered && isEnabled ? SettingsStyle.keycapHoverBorder : SettingsStyle.keycapBorder).cgColor
                layer?.borderWidth = 1
                label.textColor = .labelColor
            } else {
                layer?.backgroundColor = SettingsStyle.keycapEmptyFill.cgColor
                layer?.borderColor = (isHovered && isEnabled ? SettingsStyle.keycapHoverBorder : SettingsStyle.keycapBorder).cgColor
                layer?.borderWidth = 1
                label.textColor = .secondaryLabelColor
            }
        }
    }

    nonisolated static func carbonModifiers(_ flags: NSEvent.ModifierFlags) -> UInt32 {
        var modifiers: UInt32 = 0
        if flags.contains(.command) {
            if HotKeyModifiers.isRightCommandOnly(flags) {
                modifiers |= HotKeyModifiers.rightCommand
            } else {
                modifiers |= UInt32(cmdKey)
            }
        }
        if flags.contains(.option) { modifiers |= UInt32(optionKey) }
        if flags.contains(.control) { modifiers |= UInt32(controlKey) }
        if flags.contains(.shift) { modifiers |= UInt32(shiftKey) }
        return modifiers
    }
}
