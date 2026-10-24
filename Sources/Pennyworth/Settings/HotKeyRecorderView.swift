import AppKit
import Carbon

@MainActor final class HotKeyRecorderView: NSView {
    private(set) var binding: HotKeyPreset?
    private var originalBinding: HotKeyPreset?
    private(set) var isRecording = false
    private let label = NSTextField(labelWithString: "")
    private let hint = NSTextField(labelWithString: "点击后按下快捷键")

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
        setAccessibilityLabel("快捷键录入")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        beginRecording()
        window?.makeFirstResponder(self)
    }

    override func keyDown(with event: NSEvent) {
        _ = processKey(keyCode: UInt32(event.keyCode), modifiers: Self.carbonModifiers(event.modifierFlags))
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard isRecording else { return super.performKeyEquivalent(with: event) }
        return processKey(keyCode: UInt32(event.keyCode), modifiers: Self.carbonModifiers(event.modifierFlags))
    }

    func setBinding(_ binding: HotKeyPreset?) {
        self.binding = binding
        updateDisplay()
    }

    func beginRecording() {
        originalBinding = binding
        isRecording = true
        hint.stringValue = "按下快捷键，Esc 取消"
        layer?.borderColor = NSColor.controlAccentColor.cgColor
    }

    @discardableResult
    func processKey(keyCode: UInt32, modifiers: UInt32) -> Bool {
        if keyCode == UInt32(kVK_Escape) {
            binding = originalBinding
            isRecording = false
            updateDisplay()
            return true
        }
        if keyCode == UInt32(kVK_Delete) || keyCode == UInt32(kVK_ForwardDelete) {
            binding = nil
            isRecording = false
            updateDisplay()
            return true
        }
        guard modifiers != 0 || HotKeyPreset.supportsWithoutModifier(keyCode) else {
            hint.stringValue = "快捷键必须包含 ⌘、⌥、⌃ 或 ⇧"
            return false
        }
        binding = .custom(keyCode: keyCode, modifiers: modifiers)
        isRecording = false
        updateDisplay()
        return true
    }

    func clearBinding() {
        binding = nil
        isRecording = false
        updateDisplay()
    }

    private func updateDisplay() {
        label.stringValue = binding?.title ?? "未设置"
        if !isRecording { hint.stringValue = "点击后按下快捷键" }
        layer?.borderColor = NSColor.separatorColor.cgColor
    }

    private static func carbonModifiers(_ flags: NSEvent.ModifierFlags) -> UInt32 {
        var modifiers: UInt32 = 0
        if flags.contains(.command) { modifiers |= UInt32(cmdKey) }
        if flags.contains(.option) { modifiers |= UInt32(optionKey) }
        if flags.contains(.control) { modifiers |= UInt32(controlKey) }
        if flags.contains(.shift) { modifiers |= UInt32(shiftKey) }
        return modifiers
    }
}
