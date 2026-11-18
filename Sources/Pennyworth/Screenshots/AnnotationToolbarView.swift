import AppKit

/// Compact annotation toolbar hosted inside the overlay view near the selection.
/// Only sends semantic actions; all state lives in the overlay view's AnnotationEditor.
final class AnnotationToolbarView: NSView {
    var onToolSelected: ((AnnotationTool) -> Void)?
    var onColorSelected: ((RGBAColor) -> Void)?
    var onLineWidthChanged: ((CGFloat) -> Void)?
    var onFontSizeChanged: ((CGFloat) -> Void)?
    var onUndo: (() -> Void)?
    var onRedo: (() -> Void)?
    var onCopy: (() -> Void)?
    var onSave: (() -> Void)?
    var onPin: (() -> Void)?
    var onCancel: (() -> Void)?

    private var toolButtons: [AnnotationTool: NSButton] = [:]
    private var undoButton: NSButton?
    private var redoButton: NSButton?
    private let lineWidthPopup = NSPopUpButton()
    private let fontSizePopup = NSPopUpButton()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        layer?.cornerRadius = 6
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.separatorColor.cgColor
        buildControls()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private func buildControls() {
        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.spacing = 4
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
        ])
        let symbols: [AnnotationTool: String] = [
            .selection: "cursorarrow", .rectangle: "rectangle", .ellipse: "ellipse",
            .arrow: "arrow.right", .pen: "pencil.tip", .text: "character", .mosaic: "square.grid.3x3",
        ]
        for tool in AnnotationTool.allCases {
            let button = makeButton(symbol: symbols[tool] ?? "questionmark",
                                    tooltip: L10n.tr("screenshot.tool.\(tool.rawValue)")) { [weak self] in
                self?.onToolSelected?(tool)
            }
            button.setAccessibilityLabel(L10n.tr("screenshot.tool.\(tool.rawValue)"))
            toolButtons[tool] = button
            stack.addArrangedSubview(button)
        }
        stack.addArrangedSubview(separator())
        for color in [RGBAColor.red, .orange, .yellow, .green, .blue, .black, .white] {
            let swatch = NSButton(title: "", target: nil, action: nil)
            swatch.isBordered = false
            swatch.wantsLayer = true
            swatch.layer?.backgroundColor = color.cgColor
            swatch.layer?.cornerRadius = 7
            swatch.layer?.borderWidth = 1
            swatch.layer?.borderColor = NSColor.separatorColor.cgColor
            swatch.widthAnchor.constraint(equalToConstant: 14).isActive = true
            swatch.heightAnchor.constraint(equalToConstant: 14).isActive = true
            swatch.setAccessibilityLabel(L10n.tr("screenshot.style.color"))
            swatch.target = self
            swatch.action = #selector(colorClicked(_:))
            swatch.tag = stack.arrangedSubviews.count
            swatch.toolTip = L10n.tr("screenshot.style.color")
            colorButtons.append(swatch)
            colors.append(color)
            stack.addArrangedSubview(swatch)
        }
        stack.addArrangedSubview(separator())
        configurePopup(lineWidthPopup, values: [2, 3, 5, 8], action: #selector(lineWidthChanged(_:)))
        configurePopup(fontSizePopup, values: [12, 16, 24, 32], action: #selector(fontSizeChanged(_:)))
        stack.addArrangedSubview(lineWidthPopup)
        stack.addArrangedSubview(fontSizePopup)
        stack.addArrangedSubview(separator())
        undoButton = makeButton(symbol: "arrow.uturn.backward", tooltip: L10n.tr("screenshot.action.undo")) { [weak self] in self?.onUndo?() }
        redoButton = makeButton(symbol: "arrow.uturn.forward", tooltip: L10n.tr("screenshot.action.redo")) { [weak self] in self?.onRedo?() }
        stack.addArrangedSubview(undoButton!)
        stack.addArrangedSubview(redoButton!)
        stack.addArrangedSubview(separator())
        stack.addArrangedSubview(makeButton(symbol: "doc.on.doc", tooltip: L10n.tr("screenshot.action.copy")) { [weak self] in self?.onCopy?() })
        stack.addArrangedSubview(makeButton(symbol: "square.and.arrow.down", tooltip: L10n.tr("screenshot.action.save")) { [weak self] in self?.onSave?() })
        stack.addArrangedSubview(makeButton(symbol: "pin", tooltip: L10n.tr("screenshot.action.pin")) { [weak self] in self?.onPin?() })
        stack.addArrangedSubview(makeButton(symbol: "xmark", tooltip: L10n.tr("screenshot.action.cancel")) { [weak self] in self?.onCancel?() })
    }

    private var colorButtons: [NSButton] = []
    private var colors: [RGBAColor] = []

    private func makeButton(symbol: String, tooltip: String, action: @escaping () -> Void) -> NSButton {
        let button = NSButton(title: "", target: nil, action: nil)
        button.isBordered = false
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: tooltip)
        button.imagePosition = .imageOnly
        button.widthAnchor.constraint(equalToConstant: 26).isActive = true
        button.heightAnchor.constraint(equalToConstant: 24).isActive = true
        button.toolTip = tooltip
        button.setAccessibilityLabel(tooltip)
        button.target = self
        button.action = #selector(buttonClicked(_:))
        actions[button] = action
        return button
    }

    private var actions: [NSButton: () -> Void] = [:]

    private func separator() -> NSBox {
        let box = NSBox()
        box.boxType = .separator
        return box
    }

    private func configurePopup(_ popup: NSPopUpButton, values: [Int], action: Selector) {
        popup.addItems(withTitles: values.map(String.init))
        popup.font = .systemFont(ofSize: 11)
        popup.target = self
        popup.action = action
        popup.widthAnchor.constraint(equalToConstant: 58).isActive = true
    }

    @objc private func buttonClicked(_ sender: NSButton) { actions[sender]?() }

    @objc private func colorClicked(_ sender: NSButton) {
        guard let index = colorButtons.firstIndex(of: sender) else { return }
        onColorSelected?(colors[index])
    }

    @objc private func lineWidthChanged(_ sender: NSPopUpButton) {
        onLineWidthChanged?(CGFloat(Double(sender.selectedItem?.title ?? "3") ?? 3))
    }

    @objc private func fontSizeChanged(_ sender: NSPopUpButton) {
        onFontSizeChanged?(CGFloat(Double(sender.selectedItem?.title ?? "16") ?? 16))
    }

    func update(editor: AnnotationEditor) {
        for (tool, button) in toolButtons {
            button.contentTintColor = tool == editor.tool ? .controlAccentColor : .labelColor
        }
        undoButton?.isEnabled = editor.history.canUndo
        redoButton?.isEnabled = editor.history.canRedo
    }
}
