import AppKit

@MainActor protocol ScreenshotOverlayViewDelegate: AnyObject {
    func overlayViewDidCancel(_ view: ScreenshotOverlayView)
    func overlayViewDidConfirm(_ view: ScreenshotOverlayView)
    func overlayView(_ view: ScreenshotOverlayView, didChangeSelection rect: CGRect?)
    func overlayViewDidBecomeActive(_ view: ScreenshotOverlayView)
    func overlayViewDidRequestSave(_ view: ScreenshotOverlayView)
    func overlayViewDidRequestPin(_ view: ScreenshotOverlayView)
}

/// One frozen display: window hover highlighting, click-to-select-window,
/// free drag creation, move and eight-handle resize, pixel size label.
final class ScreenshotOverlayView: NSView {
    let display: CapturedDisplay
    private let windows: [WindowDescriptor]
    private let mainDisplayHeight: CGFloat
    private let hitTester: WindowHitTester
    var selection: SelectionModel
    var highlightedWindow: WindowHit?
    private let backgroundImage: NSImage
    var editor = AnnotationEditor()
    var toolbar: AnnotationToolbarView?
    var textField: NSTextField?
    var textEditOrigin: CGPoint?

    weak var delegate: ScreenshotOverlayViewDelegate?

    private enum Gesture: Equatable {
        case none
        case creating(start: CGPoint)
        case moving(start: CGPoint, original: CGRect)
        case resizing(handle: SelectionHandle, start: CGPoint, original: CGRect)
        case annotating
    }
    private var gesture: Gesture = .none

    init(frame: NSRect, display: CapturedDisplay, windows: [WindowDescriptor],
         mainDisplayHeight: CGFloat, ownPID: pid_t) {
        self.display = display
        self.windows = windows
        self.mainDisplayHeight = mainDisplayHeight
        self.hitTester = WindowHitTester(ownPID: ownPID)
        self.selection = SelectionModel(bounds: display.localBounds)
        self.backgroundImage = NSImage(cgImage: display.image, size: display.localBounds.size)
        super.init(frame: frame)
        let options: NSTrackingArea.Options = [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect]
        addTrackingArea(NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var acceptsFirstResponder: Bool { true }
    override var isFlipped: Bool { false }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        backgroundImage.draw(in: bounds)
        drawDimmingMask()
        drawWindowHighlight()
        drawSelection()
        drawAnnotations()
        layoutToolbar()
    }

    private func drawDimmingMask() {
        let path = NSBezierPath(rect: bounds)
        if let rect = selection.rect {
            path.append(NSBezierPath(rect: rect))
        }
        path.windingRule = .evenOdd
        NSColor.black.withAlphaComponent(0.35).setFill()
        path.fill()
    }

    private func drawWindowHighlight() {
        guard selection.rect == nil, let hit = highlightedWindow else { return }
        NSColor.systemBlue.setStroke()
        let path = NSBezierPath(rect: hit.localBounds)
        path.lineWidth = 2
        path.stroke()
    }

    private func drawSelection() {
        guard let rect = selection.rect else { return }
        NSColor.white.setStroke()
        let border = NSBezierPath(rect: rect)
        border.lineWidth = 1
        border.stroke()
        for handle in SelectionHandle.allCases {
            let handleRect = SelectionModel.handleRect(for: handle, in: rect)
            NSColor.white.setFill()
            NSBezierPath(rect: handleRect).fill()
            NSColor.systemBlue.setStroke()
            NSBezierPath(rect: handleRect).stroke()
        }
        drawSizeLabel(for: rect)
    }

    private func drawSizeLabel(for rect: CGRect) {
        let pixels = ScreenGeometry.pixelRect(for: rect, in: display)
        let text = "\(Int(pixels.width)) × \(Int(pixels.height))" as NSString
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.white,
        ]
        let textSize = text.size(withAttributes: attributes)
        let padding = CGSize(width: 8, height: 4)
        let labelSize = CGSize(width: textSize.width + padding.width * 2, height: textSize.height + padding.height * 2)
        // Prefer above the selection; flip below when there is no room at the top of the display.
        var origin = CGPoint(x: rect.midX - labelSize.width / 2, y: rect.maxY + 6)
        if origin.y + labelSize.height > bounds.maxY { origin.y = rect.minY - labelSize.height - 6 }
        origin.x = min(max(origin.x, bounds.minX + 4), bounds.maxX - labelSize.width - 4)
        origin.y = max(origin.y, bounds.minY + 4)
        let labelRect = CGRect(origin: origin, size: labelSize)
        NSColor.black.withAlphaComponent(0.75).setFill()
        NSBezierPath(roundedRect: labelRect, xRadius: 4, yRadius: 4).fill()
        text.draw(at: CGPoint(x: origin.x + padding.width, y: origin.y + padding.height), withAttributes: attributes)
    }

    // MARK: - Mouse

    private func point(from event: NSEvent) -> CGPoint {
        convert(event.locationInWindow, from: nil)
    }

    override func mouseMoved(with event: NSEvent) {
        let point = point(from: event)
        guard gesture == .none else { return }
        if selection.rect == nil {
            highlightedWindow = hitTester.hit(atLocalPoint: point, display: display.descriptor,
                                              windows: windows, mainDisplayHeight: mainDisplayHeight)
            needsDisplay = true
        }
        updateCursor(at: point)
    }

    override func mouseDown(with event: NSEvent) {
        delegate?.overlayViewDidBecomeActive(self)
        if textField != nil { commitTextEditing() }
        let point = point(from: event)
        if editor.tool == .text, let rect = selection.rect, rect.contains(point) {
            beginTextEditing(at: point)
            return
        }
        if editor.tool != .selection, selection.rect != nil, selection.contains(point) {
            gesture = .annotating
            editor = editor.beginShape(at: localPoint(point))
            needsDisplay = true
            return
        }
        // Selection geometry locks once the first annotation is committed.
        guard editor.history.current.isEmpty else { return }
        if let rect = selection.rect {
            if let handle = selection.handle(at: point) {
                gesture = .resizing(handle: handle, start: point, original: rect)
                return
            }
            if selection.contains(point) {
                gesture = .moving(start: point, original: rect)
                return
            }
        }
        gesture = .creating(start: point)
    }

    override func mouseDragged(with event: NSEvent) {
        let point = point(from: event)
        if case .annotating = gesture {
            editor = editor.updateShape(to: localPoint(point))
            needsDisplay = true
            return
        }
        let newRect: CGRect?
        switch gesture {
        case .creating(let start):
            newRect = selection.dragRect(from: start, to: point)
        case .moving(let start, let original):
            newRect = selection.moved(original: original, from: start, to: point)
        case .resizing(let handle, let start, let original):
            newRect = selection.resized(handle: handle, original: original, from: start, to: point)
        case .none, .annotating:
            return
        }
        selection = SelectionModel(bounds: display.localBounds, rect: newRect)
        delegate?.overlayView(self, didChangeSelection: newRect)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        if case .annotating = gesture {
            editor = editor.endShape()
            gesture = .none
            updateToolbar()
            needsDisplay = true
            return
        }
        defer { gesture = .none }
        let point = point(from: event)
        // A click (below the drag threshold) selects the window under the cursor or clears
        // any previous selection; a completed drag keeps the rect it just produced.
        if case .creating(let start) = gesture, !SelectionModel.isDrag(from: start, to: point) {
            let hit = hitTester.hit(atLocalPoint: point, display: display.descriptor,
                                    windows: windows, mainDisplayHeight: mainDisplayHeight)
            let rect = hit.map { ScreenGeometry.clamped($0.localBounds, to: display.localBounds) }
            selection = SelectionModel(bounds: display.localBounds, rect: rect)
            delegate?.overlayView(self, didChangeSelection: rect)
            needsDisplay = true
        }
    }

    private func updateCursor(at point: CGPoint) {
        if selection.rect == nil || selection.contains(point) && selection.handle(at: point) == nil {
            NSCursor.crosshair.set()
        } else {
            NSCursor.arrow.set()
        }
    }

    // MARK: - Keyboard

    override func keyDown(with event: NSEvent) {
        if event.modifierFlags.contains(.command), handleCommandShortcut(event) { return }
        switch event.keyCode {
        case 53: delegate?.overlayViewDidCancel(self) // Escape
        case 36, 76: delegate?.overlayViewDidConfirm(self) // Return / keypad Enter
        default: super.keyDown(with: event)
        }
    }

    override func cancelOperation(_ sender: Any?) {
        delegate?.overlayViewDidCancel(self)
    }
}
