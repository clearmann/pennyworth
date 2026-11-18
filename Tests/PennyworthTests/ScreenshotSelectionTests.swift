import CoreGraphics
import XCTest
@testable import Pennyworth

final class ScreenshotSelectionTests: XCTestCase {
    private let bounds = CGRect(x: 0, y: 0, width: 800, height: 600)
    private var model: SelectionModel { SelectionModel(bounds: bounds) }

    func testDragThresholdDistinguishesClickFromDrag() {
        XCTAssertFalse(SelectionModel.isDrag(from: .zero, to: CGPoint(x: 2, y: 2)))
        XCTAssertTrue(SelectionModel.isDrag(from: .zero, to: CGPoint(x: 3, y: 0)))
        XCTAssertTrue(SelectionModel.isDrag(from: .zero, to: CGPoint(x: 0, y: -3)))
    }

    func testClickDragRectIsNil() {
        XCTAssertNil(model.dragRect(from: CGPoint(x: 100, y: 100), to: CGPoint(x: 101, y: 101)))
    }

    func testDragRectStandardizesReverseDrag() {
        let rect = model.dragRect(from: CGPoint(x: 200, y: 200), to: CGPoint(x: 100, y: 150))
        XCTAssertEqual(rect, CGRect(x: 100, y: 150, width: 100, height: 50))
    }

    func testDragRectClampsToDisplay() {
        let rect = model.dragRect(from: CGPoint(x: 700, y: 500), to: CGPoint(x: 900, y: 700))
        XCTAssertEqual(rect, CGRect(x: 700, y: 500, width: 100, height: 100))
    }

    func testMoveTranslatesRect() {
        let original = CGRect(x: 100, y: 100, width: 200, height: 100)
        let moved = model.moved(original: original, from: CGPoint(x: 150, y: 150), to: CGPoint(x: 200, y: 180))
        XCTAssertEqual(moved, CGRect(x: 150, y: 130, width: 200, height: 100))
    }

    func testMoveClampsAtDisplayEdges() {
        let original = CGRect(x: 100, y: 100, width: 200, height: 100)
        let moved = model.moved(original: original, from: .zero, to: CGPoint(x: 1000, y: 1000))
        XCTAssertEqual(moved, CGRect(x: 600, y: 500, width: 200, height: 100))
        let movedBack = model.moved(original: original, from: .zero, to: CGPoint(x: -1000, y: -1000))
        XCTAssertEqual(movedBack, CGRect(x: 0, y: 0, width: 200, height: 100))
    }

    func testResizeEachHandleMovesOnlyItsOwnEdges() {
        let original = CGRect(x: 100, y: 100, width: 200, height: 100)
        // Uniform delta of (+10, +10): left/bottom edges move right/up (shrinking),
        // right/top edges move right/up (growing). Only a handle's own edges may change.
        let cases: [(SelectionHandle, CGRect)] = [
            (.topLeft, CGRect(x: 110, y: 100, width: 190, height: 110)),
            (.top, CGRect(x: 100, y: 100, width: 200, height: 110)),
            (.topRight, CGRect(x: 100, y: 100, width: 210, height: 110)),
            (.right, CGRect(x: 100, y: 100, width: 210, height: 100)),
            (.bottomRight, CGRect(x: 100, y: 110, width: 210, height: 90)),
            (.bottom, CGRect(x: 100, y: 110, width: 200, height: 90)),
            (.bottomLeft, CGRect(x: 110, y: 110, width: 190, height: 90)),
            (.left, CGRect(x: 110, y: 100, width: 190, height: 100)),
        ]
        for (handle, expected) in cases {
            let actual = model.resized(handle: handle, original: original, from: .zero, to: CGPoint(x: 10, y: 10))
            XCTAssertEqual(actual, expected, "handle \(handle)")
        }
    }

    func testResizeAcrossOppositeEdgeFlipsRect() {
        let original = CGRect(x: 100, y: 100, width: 200, height: 100)
        // Drag the right edge 300pt leftwards: past the left edge, producing a flipped rect.
        let rect = model.resized(handle: .right, original: original, from: .zero, to: CGPoint(x: -300, y: 0))
        XCTAssertEqual(rect, CGRect(x: 0, y: 100, width: 100, height: 100))
    }

    func testResizeClampsToDisplayBounds() {
        let original = CGRect(x: 100, y: 100, width: 200, height: 100)
        let rect = model.resized(handle: .topRight, original: original, from: .zero, to: CGPoint(x: 2000, y: 2000))
        XCTAssertEqual(rect, CGRect(x: 100, y: 100, width: 700, height: 500))
    }

    func testHandleHitTestingUsesSlop() {
        let rect = CGRect(x: 100, y: 100, width: 200, height: 100)
        let model = SelectionModel(bounds: bounds, rect: rect)
        XCTAssertEqual(model.handle(at: CGPoint(x: 100, y: 200)), .topLeft)
        XCTAssertEqual(model.handle(at: CGPoint(x: 200, y: 200)), .top)
        XCTAssertEqual(model.handle(at: CGPoint(x: 300, y: 200)), .topRight)
        XCTAssertEqual(model.handle(at: CGPoint(x: 300, y: 150)), .right)
        XCTAssertEqual(model.handle(at: CGPoint(x: 300, y: 100)), .bottomRight)
        XCTAssertEqual(model.handle(at: CGPoint(x: 200, y: 100)), .bottom)
        XCTAssertEqual(model.handle(at: CGPoint(x: 100, y: 100)), .bottomLeft)
        XCTAssertEqual(model.handle(at: CGPoint(x: 100, y: 150)), .left)
        // 5pt outside the top-left corner still hits due to slop; the center hits no handle.
        XCTAssertEqual(model.handle(at: CGPoint(x: 95, y: 205)), .topLeft)
        XCTAssertNil(model.handle(at: CGPoint(x: 200, y: 150)))
        XCTAssertNil(model.handle(at: CGPoint(x: 400, y: 400)))
    }

    func testContainsOnlyInsideRect() {
        let model = SelectionModel(bounds: bounds, rect: CGRect(x: 100, y: 100, width: 200, height: 100))
        XCTAssertTrue(model.contains(CGPoint(x: 150, y: 150)))
        XCTAssertFalse(model.contains(CGPoint(x: 50, y: 50)))
        XCTAssertFalse(SelectionModel(bounds: bounds).contains(.zero))
    }
}
