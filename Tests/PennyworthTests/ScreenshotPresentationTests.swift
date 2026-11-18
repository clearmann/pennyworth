import XCTest
@testable import Pennyworth

@MainActor
final class ScreenshotPresentationTests: XCTestCase {
    private func makeDisplay(size: CGSize = CGSize(width: 800, height: 600)) -> CapturedDisplay {
        let descriptor = DisplayDescriptor(id: 1, quartzFrame: CGRect(origin: .zero, size: size),
                                           cocoaFrame: CGRect(origin: .zero, size: size))
        let provider = CGDataProvider(data: Data([UInt8](repeating: 90, count: Int(size.width * size.height * 4))) as CFData)!
        let image = CGImage(width: Int(size.width), height: Int(size.height), bitsPerComponent: 8, bitsPerPixel: 32,
                            bytesPerRow: Int(size.width) * 4, space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
        return CapturedDisplay(descriptor: descriptor, image: image)
    }

    private func makeView() -> ScreenshotOverlayView {
        ScreenshotOverlayView(frame: NSRect(x: 0, y: 0, width: 800, height: 600), display: makeDisplay(),
                              windows: [], mainDisplayHeight: 600, ownPID: 1)
    }

    private func mouseEvent(type: NSEvent.EventType, at point: CGPoint) -> NSEvent {
        NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: 0,
                           windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
    }

    // MARK: - Panel

    func testOverlayPanelConfiguration() {
        let panel = ScreenshotOverlayPanel(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
                                           styleMask: [], backing: .buffered, defer: false)
        XCTAssertEqual(panel.level, .screenSaver)
        XCTAssertTrue(panel.canBecomeKey)
        XCTAssertTrue(panel.collectionBehavior.contains(.canJoinAllSpaces))
        XCTAssertTrue(panel.collectionBehavior.contains(.fullScreenAuxiliary))
        XCTAssertTrue(panel.acceptsMouseMovedEvents)
        XCTAssertFalse(panel.hidesOnDeactivate)
        panel.orderOut(nil)
    }

    // MARK: - Selection gestures

    func testDragCreatesSelection() {
        let view = makeView()
        view.mouseDown(with: mouseEvent(type: .leftMouseDown, at: CGPoint(x: 50, y: 50)))
        view.mouseDragged(with: mouseEvent(type: .leftMouseDragged, at: CGPoint(x: 150, y: 120)))
        view.mouseUp(with: mouseEvent(type: .leftMouseUp, at: CGPoint(x: 150, y: 120)))
        XCTAssertEqual(view.selection.rect, CGRect(x: 50, y: 50, width: 100, height: 70))
    }

    func testClickWithoutWindowClearsSelection() {
        let view = makeView()
        view.mouseDown(with: mouseEvent(type: .leftMouseDown, at: CGPoint(x: 50, y: 50)))
        view.mouseUp(with: mouseEvent(type: .leftMouseUp, at: CGPoint(x: 51, y: 51)))
        XCTAssertNil(view.selection.rect)
    }

    // MARK: - Annotation gestures

    func testShapeGestureCommitsAnnotation() {
        let view = makeView()
        view.mouseDown(with: mouseEvent(type: .leftMouseDown, at: CGPoint(x: 50, y: 50)))
        view.mouseDragged(with: mouseEvent(type: .leftMouseDragged, at: CGPoint(x: 200, y: 200)))
        view.mouseUp(with: mouseEvent(type: .leftMouseUp, at: CGPoint(x: 200, y: 200)))
        view.editor = view.editor.selectingTool(.rectangle)
        view.mouseDown(with: mouseEvent(type: .leftMouseDown, at: CGPoint(x: 60, y: 60)))
        view.mouseDragged(with: mouseEvent(type: .leftMouseDragged, at: CGPoint(x: 120, y: 120)))
        view.mouseUp(with: mouseEvent(type: .leftMouseUp, at: CGPoint(x: 120, y: 120)))
        XCTAssertEqual(view.editor.history.current.count, 1)
        guard case .rectangle(let rect)? = view.editor.history.current.first?.geometry else {
            return XCTFail("expected rectangle annotation")
        }
        // Selection-local coordinates: selection origin is (50, 50).
        XCTAssertEqual(rect, CGRect(x: 10, y: 10, width: 60, height: 60))
    }

    func testSelectionLocksAfterFirstAnnotation() {
        let view = makeView()
        view.editor = AnnotationEditor(tool: .rectangle)
        view.editor = view.editor.beginShape(at: .zero)
        view.editor = view.editor.updateShape(to: CGPoint(x: 30, y: 30))
        view.editor = view.editor.endShape()
        let original = CGRect(x: 50, y: 50, width: 100, height: 70)
        view.selection = SelectionModel(bounds: view.display.localBounds, rect: original)
        view.editor = view.editor.selectingTool(.selection)
        view.mouseDown(with: mouseEvent(type: .leftMouseDown, at: CGPoint(x: 80, y: 80)))
        view.mouseDragged(with: mouseEvent(type: .leftMouseDragged, at: CGPoint(x: 180, y: 180)))
        view.mouseUp(with: mouseEvent(type: .leftMouseUp, at: CGPoint(x: 180, y: 180)))
        XCTAssertEqual(view.selection.rect, original, "annotated selection must not move")
    }

    func testUndoRedoShortcuts() {
        let view = makeView()
        view.editor = view.editor.selectingTool(.rectangle)
        view.editor = view.editor.beginShape(at: .zero)
        view.editor = view.editor.updateShape(to: CGPoint(x: 30, y: 30))
        view.editor = view.editor.endShape()
        XCTAssertEqual(view.editor.history.current.count, 1)
        let undo = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command,
                                    timestamp: 0, windowNumber: 0, context: nil,
                                    characters: "z", charactersIgnoringModifiers: "z",
                                    isARepeat: false, keyCode: 6)!
        view.keyDown(with: undo)
        XCTAssertTrue(view.editor.history.current.isEmpty)
        let redo = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [.command, .shift],
                                    timestamp: 0, windowNumber: 0, context: nil,
                                    characters: "Z", charactersIgnoringModifiers: "z",
                                    isARepeat: false, keyCode: 6)!
        view.keyDown(with: redo)
        XCTAssertEqual(view.editor.history.current.count, 1)
    }

    // MARK: - Text editing

    func testTextEditingCommitAddsAnnotation() {
        let view = makeView()
        view.mouseDown(with: mouseEvent(type: .leftMouseDown, at: CGPoint(x: 50, y: 50)))
        view.mouseDragged(with: mouseEvent(type: .leftMouseDragged, at: CGPoint(x: 200, y: 200)))
        view.mouseUp(with: mouseEvent(type: .leftMouseUp, at: CGPoint(x: 200, y: 200)))
        view.editor = view.editor.selectingTool(.text)
        view.beginTextEditing(at: CGPoint(x: 80, y: 80))
        XCTAssertNotNil(view.textField)
        view.textField?.stringValue = "你好"
        view.commitTextEditing()
        XCTAssertNil(view.textField)
        XCTAssertEqual(view.editor.history.current.count, 1)
        guard case .text(let geometry)? = view.editor.history.current.first?.geometry else {
            return XCTFail("expected text annotation")
        }
        XCTAssertEqual(geometry.text, "你好")
    }

    func testBlankTextIsNotCommitted() {
        let view = makeView()
        view.beginTextEditing(at: CGPoint(x: 80, y: 80))
        view.textField?.stringValue = "   "
        view.commitTextEditing()
        XCTAssertTrue(view.editor.history.current.isEmpty)
        XCTAssertNil(view.textField)
    }

    // MARK: - Toolbar

    func testToolbarAppearsWithinBoundsAfterSelection() {
        let view = makeView()
        view.mouseDown(with: mouseEvent(type: .leftMouseDown, at: CGPoint(x: 300, y: 300)))
        view.mouseDragged(with: mouseEvent(type: .leftMouseDragged, at: CGPoint(x: 500, y: 400)))
        view.mouseUp(with: mouseEvent(type: .leftMouseUp, at: CGPoint(x: 500, y: 400)))
        view.layoutToolbar()
        let toolbar = view.toolbar
        XCTAssertNotNil(toolbar)
        XCTAssertNotNil(toolbar?.superview)
        if let frame = toolbar?.frame {
            XCTAssertTrue(view.bounds.contains(frame.origin))
            XCTAssertLessThanOrEqual(frame.maxX, view.bounds.maxX)
            XCTAssertLessThanOrEqual(frame.maxY, view.bounds.maxY)
        }
    }

    func testToolbarRemovedWhenSelectionClears() {
        let view = makeView()
        view.mouseDown(with: mouseEvent(type: .leftMouseDown, at: CGPoint(x: 300, y: 300)))
        view.mouseDragged(with: mouseEvent(type: .leftMouseDragged, at: CGPoint(x: 500, y: 400)))
        view.mouseUp(with: mouseEvent(type: .leftMouseUp, at: CGPoint(x: 500, y: 400)))
        view.layoutToolbar()
        XCTAssertNotNil(view.toolbar)
        // Click empty space (no window hit) clears the selection and the toolbar.
        view.mouseDown(with: mouseEvent(type: .leftMouseDown, at: CGPoint(x: 50, y: 50)))
        view.mouseUp(with: mouseEvent(type: .leftMouseUp, at: CGPoint(x: 50, y: 50)))
        view.layoutToolbar()
        XCTAssertNil(view.toolbar)
    }
}
