import AppKit

/// Annotation integration: rendering, toolbar, text editing and keyboard shortcuts.
extension ScreenshotOverlayView {
    /// Converts a view point to selection-local coordinates for the annotation model.
    func localPoint(_ point: CGPoint) -> CGPoint {
        guard let rect = selection.rect else { return point }
        return CGPoint(x: point.x - rect.minX, y: point.y - rect.minY)
    }

    func drawAnnotations() {
        guard let rect = selection.rect else { return }
        let pixelRect = ScreenGeometry.pixelRect(for: rect, in: display)
        guard let cropped = display.image.cropping(to: pixelRect),
              let context = NSGraphicsContext.current?.cgContext else { return }
        context.saveGState()
        context.translateBy(x: -rect.minX, y: -rect.minY)
        context.clip(to: CGRect(origin: .zero, size: rect.size))
        AnnotationRenderer.draw(annotations: editor.history.current, draft: editor.draft,
                                mosaicSource: cropped, scaleX: display.scaleX, scaleY: display.scaleY,
                                in: context)
        context.restoreGState()
    }

    // MARK: - Toolbar

    func updateToolbar() {
        toolbar?.update(editor: editor)
        needsDisplay = true
    }

    func layoutToolbar() {
        guard let rect = selection.rect else {
            toolbar?.removeFromSuperview()
            toolbar = nil
            return
        }
        let bar = ensureToolbar()
        bar.update(editor: editor)
        let size = bar.fittingSize
        guard size.width > 0, size.height > 0 else { return }
        var origin = CGPoint(x: rect.midX - size.width / 2, y: rect.minY - size.height - 8)
        if origin.y < bounds.minY + 4 { origin.y = rect.maxY + 8 }
        if origin.y + size.height > bounds.maxY - 4 { origin.y = max(bounds.minY + 4, rect.minY - size.height - 8) }
        origin.x = min(max(origin.x, bounds.minX + 4), bounds.maxX - size.width - 4)
        let frame = CGRect(origin: origin, size: size)
        if bar.frame != frame { bar.frame = frame }
        if bar.superview == nil { addSubview(bar) }
    }

    private func ensureToolbar() -> AnnotationToolbarView {
        if let toolbar { return toolbar }
        let bar = AnnotationToolbarView()
        bar.onToolSelected = { [weak self] tool in
            guard let self else { return }
            self.editor = self.editor.selectingTool(tool)
            self.updateToolbar()
        }
        bar.onColorSelected = { [weak self] color in
            self?.updateStyle { AnnotationStyle(color: color, lineWidth: $0.lineWidth,
                                                fontSize: $0.fontSize, mosaicBlockSize: $0.mosaicBlockSize) }
        }
        bar.onLineWidthChanged = { [weak self] width in
            self?.updateStyle { AnnotationStyle(color: $0.color, lineWidth: width,
                                                fontSize: $0.fontSize, mosaicBlockSize: $0.mosaicBlockSize) }
        }
        bar.onFontSizeChanged = { [weak self] size in
            self?.updateStyle { AnnotationStyle(color: $0.color, lineWidth: $0.lineWidth,
                                                fontSize: size, mosaicBlockSize: $0.mosaicBlockSize) }
        }
        bar.onUndo = { [weak self] in self?.undoAnnotation()
        }
        bar.onRedo = { [weak self] in self?.redoAnnotation() }
        bar.onCopy = { [weak self] in
            guard let self else { return }
            self.delegate?.overlayViewDidConfirm(self)
        }
        bar.onSave = { [weak self] in
            guard let self else { return }
            self.delegate?.overlayViewDidRequestSave(self)
        }
        bar.onPin = { [weak self] in
            guard let self else { return }
            self.delegate?.overlayViewDidRequestPin(self)
        }
        bar.onCancel = { [weak self] in
            guard let self else { return }
            self.delegate?.overlayViewDidCancel(self)
        }
        toolbar = bar
        return bar
    }

    private func updateStyle(_ transform: (AnnotationStyle) -> AnnotationStyle) {
        editor = editor.changingStyle(transform(editor.style))
        updateToolbar()
    }

    func undoAnnotation() {
        guard let history = editor.history.undo() else { return }
        editor = editor.withHistory(history)
        updateToolbar()
    }

    func redoAnnotation() {
        guard let history = editor.history.redo() else { return }
        editor = editor.withHistory(history)
        updateToolbar()
    }

    // MARK: - Text editing

    func beginTextEditing(at viewPoint: CGPoint) {
        guard textField == nil else { return }
        let local = localPoint(viewPoint)
        let field = NSTextField(frame: NSRect(x: viewPoint.x, y: viewPoint.y - 28, width: 160, height: 28))
        field.font = .systemFont(ofSize: editor.style.fontSize, weight: .medium)
        field.textColor = editor.style.color.nsColor
        field.backgroundColor = NSColor.black.withAlphaComponent(0.25)
        field.isBordered = false
        field.focusRingType = .none
        field.delegate = self
        addSubview(field)
        textField = field
        textEditOrigin = local
        window?.makeFirstResponder(field)
    }

    func commitTextEditing() {
        guard let field = textField, let origin = textEditOrigin else { return }
        let text = field.stringValue
        let height = editor.style.fontSize * 1.6
        let frame = CGRect(x: origin.x, y: origin.y - height,
                           width: max(40, field.fittingSize.width), height: height)
        discardTextField()
        editor = editor.committingText(text, frame: frame)
        updateToolbar()
        window?.makeFirstResponder(self)
    }

    func discardTextField() {
        textField?.removeFromSuperview()
        textField = nil
        textEditOrigin = nil
    }

    // MARK: - Shortcuts

    func handleCommandShortcut(_ event: NSEvent) -> Bool {
        switch event.charactersIgnoringModifiers?.lowercased() {
        case "z":
            if event.modifierFlags.contains(.shift) { redoAnnotation() } else { undoAnnotation() }
        case "c":
            delegate?.overlayViewDidConfirm(self)
        case "s":
            delegate?.overlayViewDidRequestSave(self)
        case "t":
            delegate?.overlayViewDidRequestPin(self)
        default:
            return false
        }
        return true
    }
}

extension ScreenshotOverlayView: NSTextFieldDelegate {
    public func control(_ control: NSControl, textView: NSTextView,
                        doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            commitTextEditing()
            return true
        }
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            discardTextField()
            window?.makeFirstResponder(self)
            return true
        }
        return false
    }

    public func controlTextDidEndEditing(_ obj: Notification) {
        commitTextEditing()
    }
}
