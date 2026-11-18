import XCTest
@testable import Pennyworth

@MainActor
final class ScreenshotToolbarTests: XCTestCase {
    private final class DelegateSpy: ScreenshotOverlayViewDelegate {
        var confirmCount = 0
        var saveCount = 0
        var pinCount = 0
        var cancelCount = 0
        func overlayViewDidCancel(_ view: ScreenshotOverlayView) { cancelCount += 1 }
        func overlayViewDidConfirm(_ view: ScreenshotOverlayView) { confirmCount += 1 }
        func overlayView(_ view: ScreenshotOverlayView, didChangeSelection rect: CGRect?) {}
        func overlayViewDidBecomeActive(_ view: ScreenshotOverlayView) {}
        func overlayViewDidRequestSave(_ view: ScreenshotOverlayView) { saveCount += 1 }
        func overlayViewDidRequestPin(_ view: ScreenshotOverlayView) { pinCount += 1 }
    }

    private func makeView() -> ScreenshotOverlayView {
        _ = NSApplication.shared
        let size = CGSize(width: 800, height: 600)
        let descriptor = DisplayDescriptor(id: 1, quartzFrame: CGRect(origin: .zero, size: size),
                                           cocoaFrame: CGRect(origin: .zero, size: size))
        let provider = CGDataProvider(data: Data([UInt8](repeating: 100, count: Int(size.width * size.height * 4))) as CFData)!
        let image = CGImage(width: Int(size.width), height: Int(size.height), bitsPerComponent: 8, bitsPerPixel: 32,
                            bytesPerRow: Int(size.width) * 4, space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
        let view = ScreenshotOverlayView(frame: NSRect(origin: .zero, size: size),
                                         display: CapturedDisplay(descriptor: descriptor, image: image),
                                         windows: [], mainDisplayHeight: 600, ownPID: 1)
        view.selection = SelectionModel(bounds: view.display.localBounds,
                                        rect: CGRect(x: 100, y: 100, width: 300, height: 200))
        return view
    }

    func testToolbarActionsMutateEditorAndForwardOutputActions() {
        let view = makeView()
        let spy = DelegateSpy()
        view.delegate = spy
        view.layoutToolbar()
        guard let bar = view.toolbar else { return XCTFail("toolbar missing") }

        bar.onToolSelected?(.pen)
        XCTAssertEqual(view.editor.tool, .pen)
        bar.onColorSelected?(.blue)
        XCTAssertEqual(view.editor.style.color, .blue)
        bar.onLineWidthChanged?(5)
        XCTAssertEqual(view.editor.style.lineWidth, 5)
        bar.onFontSizeChanged?(24)
        XCTAssertEqual(view.editor.style.fontSize, 24)

        // Commit one shape, then exercise undo/redo through the toolbar closures.
        view.editor = view.editor.selectingTool(.rectangle)
        view.editor = view.editor.beginShape(at: CGPoint(x: 10, y: 10))
        view.editor = view.editor.updateShape(to: CGPoint(x: 40, y: 40))
        view.editor = view.editor.endShape()
        XCTAssertEqual(view.editor.history.current.count, 1)
        bar.onUndo?()
        XCTAssertTrue(view.editor.history.current.isEmpty)
        bar.onRedo?()
        XCTAssertEqual(view.editor.history.current.count, 1)

        bar.onCopy?()
        bar.onSave?()
        bar.onPin?()
        bar.onCancel?()
        XCTAssertEqual(spy.confirmCount, 1)
        XCTAssertEqual(spy.saveCount, 1)
        XCTAssertEqual(spy.pinCount, 1)
        XCTAssertEqual(spy.cancelCount, 1)
    }

    func testMoveAndResizeThroughViewGestures() {
        let view = makeView()
        func event(_ type: NSEvent.EventType, _ point: CGPoint) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: 0,
                               windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
        }
        // Move: drag inside the selection by (+20, +30).
        view.mouseDown(with: event(.leftMouseDown, CGPoint(x: 200, y: 200)))
        view.mouseDragged(with: event(.leftMouseDragged, CGPoint(x: 220, y: 230)))
        view.mouseUp(with: event(.leftMouseUp, CGPoint(x: 220, y: 230)))
        XCTAssertEqual(view.selection.rect, CGRect(x: 120, y: 130, width: 300, height: 200))
        // Resize: drag the bottom-right handle by (+50, -20).
        view.mouseDown(with: event(.leftMouseDown, CGPoint(x: 420, y: 130)))
        view.mouseDragged(with: event(.leftMouseDragged, CGPoint(x: 470, y: 110)))
        view.mouseUp(with: event(.leftMouseUp, CGPoint(x: 470, y: 110)))
        XCTAssertEqual(view.selection.rect, CGRect(x: 120, y: 110, width: 350, height: 220))
    }
}
