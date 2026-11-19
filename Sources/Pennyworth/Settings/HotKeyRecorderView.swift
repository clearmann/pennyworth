import AppKit
import Carbon

@MainActor final class HotKeyRecorderView: NSView {
    private(set) var binding: HotKeyPreset?
    private var originalBinding: HotKeyPreset?
    private(set) var isRecording = false
    var onChange: ((HotKeyPreset?) -> Void)?
    var onRecordingStateChanged: ((Bool) -> Void)?
    private let label = NSTextField(labelWithString: "")
    private let hint = NSTextField(labelWithString: L10n.tr("hotkey.click_to_record"))

    init(binding: HotKeyPreset?) {
        self.binding = binding
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 5
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.separatorColor.cgColor
        translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 14)
        hint.font = .systemFont(ofSize: 11)
        hint.textColor = .secondaryLabelColor
        let stack = NSStackView(views: [label, hint])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 2
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 220), heightAnchor.constraint(equalToConstant: 44),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        updateDisplay()
        setAccessibilityRole(.button)
        setAccessibilityLabel(L10n.tr("hotkey.recorder_accessibility"))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var acceptsFirstResponder: Bool { true }

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
            alphaValue = isEnabled ? 1.0 : 0.5
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
        updateDisplay()
    }

    func beginRecording() {
        guard isEnabled else { return }
        originalBinding = binding
        let wasRecording = isRecording
        isRecording = true
        hint.stringValue = L10n.tr("hotkey.press_or_cancel")
        layer?.borderColor = NSColor.controlAccentColor.cgColor
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
            binding = nil
            finishRecording()
            onChange?(nil)
            return true
        }
        guard modifiers != 0 || HotKeyPreset.supportsWithoutModifier(keyCode) else {
            hint.stringValue = L10n.tr("hotkey.modifier_required")
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

    private func finishRecording() {
        let wasRecording = isRecording
        isRecording = false
        updateDisplay()
        if wasRecording {
            onRecordingStateChanged?(false)
        }
    }

    private func updateDisplay() {
        label.stringValue = binding?.title ?? L10n.tr("hotkey.not_set")
        if !isRecording { hint.stringValue = L10n.tr("hotkey.click_to_record") }
        layer?.borderColor = NSColor.separatorColor.cgColor
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
