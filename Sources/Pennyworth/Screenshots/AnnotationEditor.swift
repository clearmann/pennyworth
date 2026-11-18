import CoreGraphics

/// A value-semantic undo stack containing complete annotation snapshots.
struct AnnotationHistory: Equatable {
    let past: [[Annotation]]
    let current: [Annotation]
    let future: [[Annotation]]

    init(current: [Annotation] = []) {
        self.init(past: [], current: current, future: [])
    }

    private init(past: [[Annotation]], current: [Annotation], future: [[Annotation]]) {
        self.past = past
        self.current = current
        self.future = future
    }

    var canUndo: Bool { !past.isEmpty }
    var canRedo: Bool { !future.isEmpty }

    func committing(_ annotation: Annotation) -> AnnotationHistory {
        replacing(current + [annotation])
    }

    func replacing(_ annotations: [Annotation]) -> AnnotationHistory {
        let updatedPast = Array((past + [current]).suffix(100))
        return AnnotationHistory(past: updatedPast, current: annotations, future: [])
    }

    func undo() -> AnnotationHistory? {
        guard let previous = past.last else { return nil }
        return AnnotationHistory(
            past: Array(past.dropLast()),
            current: previous,
            future: [current] + future
        )
    }

    func redo() -> AnnotationHistory? {
        guard let next = future.first else { return nil }
        return AnnotationHistory(
            past: past + [current],
            current: next,
            future: Array(future.dropFirst())
        )
    }
}

/// Immutable annotation editing state. Coordinates are local AppKit points.
struct AnnotationEditor: Equatable {
    let history: AnnotationHistory
    let draft: Annotation?
    let tool: AnnotationTool
    let style: AnnotationStyle
    private let shapeOrigin: CGPoint?

    init(tool: AnnotationTool = .selection, style: AnnotationStyle = .default) {
        self.init(history: AnnotationHistory(), draft: nil, tool: tool, style: style, shapeOrigin: nil)
    }

    private init(
        history: AnnotationHistory,
        draft: Annotation?,
        tool: AnnotationTool,
        style: AnnotationStyle,
        shapeOrigin: CGPoint?
    ) {
        self.history = history
        self.draft = draft
        self.tool = tool
        self.style = style
        self.shapeOrigin = shapeOrigin
    }

    func selectingTool(_ tool: AnnotationTool) -> AnnotationEditor {
        AnnotationEditor(history: history, draft: nil, tool: tool, style: style, shapeOrigin: nil)
    }

    func changingStyle(_ style: AnnotationStyle) -> AnnotationEditor {
        AnnotationEditor(
            history: history,
            draft: draft,
            tool: tool,
            style: style,
            shapeOrigin: shapeOrigin
        )
    }

    /// Replaces the undo stack, e.g. after undo()/redo(). Clears any in-progress draft.
    func withHistory(_ history: AnnotationHistory) -> AnnotationEditor {
        AnnotationEditor(history: history, draft: nil, tool: tool, style: style, shapeOrigin: nil)
    }

    func committingText(_ text: String, frame: CGRect) -> AnnotationEditor {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return self }
        let annotation = Annotation(
            geometry: .text(TextGeometry(frame: frame, text: text)),
            style: style
        )
        return AnnotationEditor(
            history: history.committing(annotation),
            draft: draft,
            tool: tool,
            style: style,
            shapeOrigin: shapeOrigin
        )
    }

    func beginShape(at point: CGPoint) -> AnnotationEditor {
        let geometry: AnnotationGeometry
        switch tool {
        case .rectangle:
            geometry = .rectangle(CGRect(origin: point, size: .zero))
        case .ellipse:
            geometry = .ellipse(CGRect(origin: point, size: .zero))
        case .arrow:
            geometry = .arrow(ArrowGeometry(start: point, end: point))
        case .pen:
            geometry = .pen([point])
        case .mosaic:
            geometry = .mosaic(CGRect(origin: point, size: .zero))
        case .selection, .text:
            return self
        }
        return replacingDraft(Annotation(geometry: geometry, style: style), shapeOrigin: point)
    }

    func updateShape(to point: CGPoint) -> AnnotationEditor {
        guard let draft else { return self }
        let geometry: AnnotationGeometry
        switch draft.geometry {
        case .rectangle:
            guard let shapeOrigin else { return self }
            geometry = .rectangle(ScreenGeometry.standardized(from: shapeOrigin, to: point))
        case .ellipse:
            guard let shapeOrigin else { return self }
            geometry = .ellipse(ScreenGeometry.standardized(from: shapeOrigin, to: point))
        case .arrow(let arrow):
            geometry = .arrow(ArrowGeometry(start: arrow.start, end: point))
        case .pen(let points):
            guard let last = points.last, distance(from: last, to: point) >= 1 else { return self }
            geometry = .pen(points + [point])
        case .mosaic:
            guard let shapeOrigin else { return self }
            geometry = .mosaic(ScreenGeometry.standardized(from: shapeOrigin, to: point))
        case .text:
            return self
        }
        return replacingDraft(draft.withGeometry(geometry), shapeOrigin: shapeOrigin)
    }

    func endShape() -> AnnotationEditor {
        guard let draft else { return self }
        let updatedHistory = isCommittable(draft) ? history.committing(draft) : history
        return AnnotationEditor(
            history: updatedHistory,
            draft: nil,
            tool: tool,
            style: style,
            shapeOrigin: nil
        )
    }

    private func replacingDraft(_ draft: Annotation, shapeOrigin: CGPoint?) -> AnnotationEditor {
        AnnotationEditor(
            history: history,
            draft: draft,
            tool: tool,
            style: style,
            shapeOrigin: shapeOrigin
        )
    }

    private func distance(from start: CGPoint, to end: CGPoint) -> CGFloat {
        hypot(end.x - start.x, end.y - start.y)
    }

    private func isCommittable(_ annotation: Annotation) -> Bool {
        switch annotation.geometry {
        case .rectangle(let rect), .ellipse(let rect), .mosaic(let rect):
            return rect.width > 0 && rect.height > 0
        case .arrow(let arrow):
            return arrow.start != arrow.end
        case .pen(let points):
            return points.count > 1
        case .text:
            return false
        }
    }
}
