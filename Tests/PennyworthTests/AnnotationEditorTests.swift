import CoreGraphics
import XCTest
@testable import Pennyworth

final class AnnotationEditorTests: XCTestCase {
    func testRectangleGestureCommitsStandardizedGeometryOnce() {
        let editor = AnnotationEditor(tool: .rectangle)
        let began = editor.beginShape(at: CGPoint(x: 20, y: 30))

        XCTAssertNotNil(began.draft)
        XCTAssertTrue(began.history.current.isEmpty)

        let ended = began
            .updateShape(to: CGPoint(x: 10, y: 5))
            .updateShape(to: CGPoint(x: 0, y: 10))
            .endShape()

        XCTAssertNil(ended.draft)
        XCTAssertEqual(ended.history.current.count, 1)
        XCTAssertEqual(
            ended.history.current.first?.geometry,
            .rectangle(CGRect(x: 0, y: 10, width: 20, height: 20))
        )
    }

    func testEllipseGestureCommitsStandardizedGeometry() {
        let ended = AnnotationEditor(tool: .ellipse)
            .beginShape(at: CGPoint(x: 50, y: 60))
            .updateShape(to: CGPoint(x: 20, y: 10))
            .endShape()

        XCTAssertEqual(ended.history.current.count, 1)
        XCTAssertEqual(
            ended.history.current.first?.geometry,
            .ellipse(CGRect(x: 20, y: 10, width: 30, height: 50))
        )
        XCTAssertNil(ended.draft)
    }

    func testArrowGesturePreservesStartAndEnd() {
        let editor = AnnotationEditor(tool: .arrow)
        let began = editor.beginShape(at: CGPoint(x: 5, y: 8))
        let updated = began.updateShape(to: CGPoint(x: 30, y: 40))

        XCTAssertEqual(updated.draft?.geometry, .arrow(ArrowGeometry(
            start: CGPoint(x: 5, y: 8),
            end: CGPoint(x: 30, y: 40)
        )))
        XCTAssertTrue(updated.history.current.isEmpty)

        let ended = updated.endShape()
        XCTAssertEqual(ended.history.current.count, 1)
        XCTAssertNil(ended.draft)
    }

    func testPenGestureAccumulatesPointsButCommitsOneStep() {
        let editor = AnnotationEditor(tool: .pen)
        let began = editor.beginShape(at: .zero)
        let updated = began
            .updateShape(to: CGPoint(x: 2, y: 0))
            .updateShape(to: CGPoint(x: 4, y: 3))

        XCTAssertEqual(updated.draft?.geometry, .pen([
            .zero,
            CGPoint(x: 2, y: 0),
            CGPoint(x: 4, y: 3),
        ]))
        XCTAssertTrue(updated.history.current.isEmpty)

        let ended = updated.endShape()
        XCTAssertEqual(ended.history.current.count, 1)
        XCTAssertEqual(ended.history.past.count, 1)
        XCTAssertNil(ended.draft)
    }

    func testMosaicGestureCommitsStandardizedGeometry() {
        let ended = AnnotationEditor(tool: .mosaic)
            .beginShape(at: CGPoint(x: 100, y: 80))
            .updateShape(to: CGPoint(x: 40, y: 20))
            .endShape()

        XCTAssertEqual(ended.history.current.count, 1)
        XCTAssertEqual(
            ended.history.current.first?.geometry,
            .mosaic(CGRect(x: 40, y: 20, width: 60, height: 60))
        )
        XCTAssertNil(ended.draft)
    }

    func testSelectionAndTextToolsDoNotBeginShapeDrafts() {
        XCTAssertNil(AnnotationEditor(tool: .selection).beginShape(at: .zero).draft)
        XCTAssertNil(AnnotationEditor(tool: .text).beginShape(at: .zero).draft)
    }

    func testTextCommitUsesFrameAndCurrentStyle() {
        let style = AnnotationStyle(color: .blue, lineWidth: 2, fontSize: 24, mosaicBlockSize: 8)
        let frame = CGRect(x: 10, y: 20, width: 120, height: 30)
        let editor = AnnotationEditor(tool: .text, style: style).committingText("Hello", frame: frame)

        XCTAssertEqual(editor.history.current.count, 1)
        XCTAssertEqual(
            editor.history.current.first?.geometry,
            .text(TextGeometry(frame: frame, text: "Hello"))
        )
        XCTAssertEqual(editor.history.current.first?.style, style)
        XCTAssertNil(editor.draft)
    }

    func testToolAndStyleChangesDoNotCreateHistorySteps() {
        let committed = AnnotationEditor(tool: .rectangle)
            .beginShape(at: .zero)
            .updateShape(to: CGPoint(x: 10, y: 10))
            .endShape()
        let style = AnnotationStyle(color: .green, lineWidth: 5, fontSize: 18, mosaicBlockSize: 16)
        let changed = committed.selectingTool(.pen).changingStyle(style)

        XCTAssertEqual(changed.history, committed.history)
        XCTAssertEqual(changed.tool, .pen)
        XCTAssertEqual(changed.style, style)
        XCTAssertNil(changed.draft)
    }

    func testDefaultEditorStyleAndTool() {
        let editor = AnnotationEditor()

        XCTAssertEqual(editor.tool, .selection)
        XCTAssertEqual(editor.style.color, .red)
        XCTAssertEqual(editor.style.lineWidth, 3)
        XCTAssertEqual(editor.style.fontSize, 16)
        XCTAssertEqual(editor.style.mosaicBlockSize, 12)
        XCTAssertTrue(editor.history.current.isEmpty)
        XCTAssertEqual(AnnotationTool.allCases.count, 7)
    }

    func testUndoAndRedoMoveCompleteSnapshotsAcrossMultipleSteps() {
        let first = makeAnnotation("first")
        let second = makeAnnotation("second")
        let third = makeAnnotation("third")
        let one = AnnotationHistory().committing(first)
        let two = one.committing(second)
        let three = two.committing(third)

        XCTAssertEqual(three.current, [first, second, third])
        XCTAssertEqual(three.past, [[], [first], [first, second]])
        XCTAssertTrue(three.canUndo)
        XCTAssertFalse(three.canRedo)

        let undoneOnce = three.undo()
        XCTAssertEqual(undoneOnce?.current, [first, second])
        XCTAssertEqual(undoneOnce?.future, [[first, second, third]])

        let undoneTwice = undoneOnce?.undo()
        XCTAssertEqual(undoneTwice?.current, [first])
        XCTAssertEqual(undoneTwice?.past, [[]])

        let redoneOnce = undoneTwice?.redo()
        XCTAssertEqual(redoneOnce?.current, [first, second])
        XCTAssertEqual(redoneOnce?.future, [[first, second, third]])

        let redoneTwice = redoneOnce?.redo()
        XCTAssertEqual(redoneTwice?.current, [first, second, third])
        XCTAssertFalse(redoneTwice?.canRedo ?? true)
    }

    func testUndoAndRedoReturnNilForEmptyStacks() {
        XCTAssertNil(AnnotationHistory().undo())
        XCTAssertNil(AnnotationHistory().redo())
    }

    func testNewCommitClearsRedoStack() {
        let first = makeAnnotation("first")
        let second = makeAnnotation("second")
        let undone = AnnotationHistory()
            .committing(first)
            .committing(second)
            .undo()

        XCTAssertEqual(undone?.future, [[first, second]])

        let recommitted = undone?.committing(makeAnnotation("replacement"))
        XCTAssertEqual(recommitted?.future, [])
        XCTAssertFalse(recommitted?.canRedo ?? true)
        XCTAssertEqual(recommitted?.current.count, 2)
    }

    func testHistoryDropsOldestSnapshotBeyondOneHundredSteps() {
        var history = AnnotationHistory()
        for index in 0..<101 {
            history = history.committing(makeAnnotation("annotation-\(index)"))
        }

        XCTAssertEqual(history.past.count, 100)
        XCTAssertEqual(history.current.count, 101)
        XCTAssertEqual(history.past.first?.count, 1)
        XCTAssertEqual(history.past.last?.count, 100)

        for _ in 0..<100 {
            guard let undone = history.undo() else {
                return XCTFail("Expected one hundred undo steps")
            }
            history = undone
        }
        XCTAssertEqual(history.current.count, 1)
        XCTAssertFalse(history.canUndo)
        XCTAssertNil(history.undo())
    }

    func testCommittingDoesNotMutatePreviousHistoryValue() {
        let first = makeAnnotation("first")
        let original = AnnotationHistory(current: [first])
        let updated = original.committing(makeAnnotation("second"))

        XCTAssertEqual(original.current, [first])
        XCTAssertEqual(original.past, [])
        XCTAssertEqual(original.future, [])
        XCTAssertEqual(updated.current.count, 2)
        XCTAssertEqual(updated.past, [[first]])
    }

    func testReplacingAnnotationsPushesPreviousSnapshot() {
        let first = makeAnnotation("first")
        let replacement = [makeAnnotation("second"), makeAnnotation("third")]
        let history = AnnotationHistory(current: [first]).replacing(replacement)

        XCTAssertEqual(history.current, replacement)
        XCTAssertEqual(history.past, [[first]])
        XCTAssertTrue(history.canUndo)
        XCTAssertEqual(history.undo()?.current, [first])
    }

    func testPenSkipsPointsLessThanOnePointFromLastAcceptedPoint() {
        let began = AnnotationEditor(tool: .pen).beginShape(at: .zero)
        let updated = began
            .updateShape(to: CGPoint(x: 0.4, y: 0.4))
            .updateShape(to: CGPoint(x: 0.6, y: 0.6))
            .updateShape(to: CGPoint(x: 1, y: 0))
            .updateShape(to: CGPoint(x: 1.9, y: 0))
            .updateShape(to: CGPoint(x: 1, y: 1))

        XCTAssertEqual(began.draft?.geometry, .pen([.zero]))
        XCTAssertEqual(updated.draft?.geometry, .pen([
            .zero,
            CGPoint(x: 1, y: 0),
            CGPoint(x: 1, y: 1),
        ]))
        XCTAssertEqual(updated.endShape().history.current.count, 1)
        XCTAssertEqual(updated.endShape().history.past.count, 1)
    }

    func testZeroSizeShapesAreNotCommitted() {
        let tools: [AnnotationTool] = [.rectangle, .ellipse, .arrow, .pen, .mosaic]
        for tool in tools {
            let ended = AnnotationEditor(tool: tool).beginShape(at: CGPoint(x: 10, y: 10)).endShape()
            XCTAssertTrue(ended.history.current.isEmpty, "tool \(tool)")
            XCTAssertTrue(ended.history.past.isEmpty, "tool \(tool)")
            XCTAssertNil(ended.draft, "tool \(tool)")
        }
    }

    func testRectShapesWithEitherZeroDimensionAreNotCommitted() {
        let zeroWidth = AnnotationEditor(tool: .rectangle)
            .beginShape(at: .zero)
            .updateShape(to: CGPoint(x: 0, y: 20))
            .endShape()
        let zeroHeight = AnnotationEditor(tool: .ellipse)
            .beginShape(at: .zero)
            .updateShape(to: CGPoint(x: 20, y: 0))
            .endShape()

        XCTAssertTrue(zeroWidth.history.current.isEmpty)
        XCTAssertNil(zeroWidth.draft)
        XCTAssertTrue(zeroHeight.history.current.isEmpty)
        XCTAssertNil(zeroHeight.draft)
    }

    func testEndShapeWithoutDraftLeavesEditorUnchanged() {
        let editor = AnnotationEditor(tool: .rectangle)
        XCTAssertEqual(editor.endShape(), editor)
    }

    func testBlankTextIsNotCommitted() {
        let editor = AnnotationEditor(tool: .text)
        for text in ["", "   ", " \n\t  \n"] {
            XCTAssertEqual(editor.committingText(text, frame: .zero), editor)
        }
        XCTAssertTrue(editor.history.current.isEmpty)
        XCTAssertFalse(editor.history.canUndo)
    }

    func testWithTextOnlyChangesTextAnnotations() {
        let id = UUID()
        let text = Annotation(
            id: id,
            geometry: .text(TextGeometry(frame: .zero, text: "old")),
            style: .default
        )
        let changed = text.withText("new")
        let rectangle = Annotation(geometry: .rectangle(.zero), style: .default)

        XCTAssertEqual(changed.id, id)
        XCTAssertEqual(changed.style, text.style)
        XCTAssertEqual(changed.geometry, .text(TextGeometry(frame: .zero, text: "new")))
        XCTAssertEqual(text.geometry, .text(TextGeometry(frame: .zero, text: "old")))
        XCTAssertEqual(rectangle.withText("ignored"), rectangle)
    }

    func testWithGeometryPreservesIdentityAndStyle() {
        let id = UUID()
        let style = AnnotationStyle(color: .orange, lineWidth: 4, fontSize: 20, mosaicBlockSize: 10)
        let annotation = Annotation(id: id, geometry: .pen([.zero]), style: style)
        let geometry = AnnotationGeometry.ellipse(CGRect(x: 1, y: 2, width: 3, height: 4))
        let changed = annotation.withGeometry(geometry)

        XCTAssertEqual(changed.id, id)
        XCTAssertEqual(changed.style, style)
        XCTAssertEqual(changed.geometry, geometry)
        XCTAssertEqual(annotation.geometry, .pen([.zero]))
    }

    private func makeAnnotation(_ text: String) -> Annotation {
        Annotation(
            geometry: .text(TextGeometry(frame: .zero, text: text)),
            style: .default
        )
    }
}
