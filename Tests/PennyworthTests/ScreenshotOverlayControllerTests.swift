import XCTest
@testable import Pennyworth

@MainActor
final class ScreenshotOverlayControllerTests: XCTestCase {
    private final class SessionDelegateSpy: ScreenshotOverlayViewDelegate {
        var cancelCount = 0
        var confirmCount = 0
        var saveCount = 0
        var pinCount = 0
        var lastRect: CGRect??

        func overlayViewDidCancel(_ view: ScreenshotOverlayView) { cancelCount += 1 }
        func overlayViewDidConfirm(_ view: ScreenshotOverlayView) { confirmCount += 1 }
        func overlayView(_ view: ScreenshotOverlayView, didChangeSelection rect: CGRect?) { lastRect = rect }
        func overlayViewDidBecomeActive(_ view: ScreenshotOverlayView) {}
        func overlayViewDidRequestSave(_ view: ScreenshotOverlayView) { saveCount += 1 }
        func overlayViewDidRequestPin(_ view: ScreenshotOverlayView) { pinCount += 1 }
    }

    private func makeDisplay() -> CapturedDisplay {
        let descriptor = DisplayDescriptor(id: 1, quartzFrame: CGRect(x: 0, y: 0, width: 100, height: 100),
                                           cocoaFrame: CGRect(x: 0, y: 0, width: 100, height: 100))
        let provider = CGDataProvider(data: Data([UInt8](repeating: 80, count: 100 * 100 * 4)) as CFData)!
        let image = CGImage(width: 100, height: 100, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: 400,
                            space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
        return CapturedDisplay(descriptor: descriptor, image: image)
    }

    func testPresentDismissLifecycleAndSelectionTracking() {
        _ = NSApplication.shared
        let controller = ScreenshotOverlayController()
        let delegate = SessionDelegateSpy()
        controller.present(snapshot: ScreenSnapshot(displays: [makeDisplay()], windows: []), delegate: delegate)
        defer { controller.dismiss() }
        let view = controller.activeView
        XCTAssertNotNil(view)
        XCTAssertNil(controller.currentSelection)
        view?.selection = SelectionModel(bounds: CGRect(x: 0, y: 0, width: 100, height: 100),
                                         rect: CGRect(x: 10, y: 10, width: 50, height: 40))
        XCTAssertEqual(controller.currentSelection?.rect, CGRect(x: 10, y: 10, width: 50, height: 40))
        let annotation = Annotation(geometry: .rectangle(CGRect(x: 1, y: 1, width: 5, height: 5)), style: .default)
        view?.editor = view!.editor.withHistory(AnnotationHistory(current: [annotation]))
        XCTAssertEqual(controller.currentSelection?.annotations, [annotation])
        controller.setOverlaysHidden(true)
        controller.setOverlaysHidden(false)
        controller.overlayViewDidConfirm(view!)
        controller.overlayViewDidCancel(view!)
        controller.overlayViewDidRequestSave(view!)
        controller.overlayViewDidRequestPin(view!)
        XCTAssertEqual(delegate.confirmCount, 1)
        XCTAssertEqual(delegate.cancelCount, 1)
        XCTAssertEqual(delegate.saveCount, 1)
        XCTAssertEqual(delegate.pinCount, 1)
        controller.dismiss()
        XCTAssertNil(controller.currentSelection)
        XCTAssertNil(controller.activeView)
    }

    func testBecomeActiveSwitchesActiveViewAndNotifiesDelegate() {
        _ = NSApplication.shared
        let controller = ScreenshotOverlayController()
        let delegate = SessionDelegateSpy()
        controller.present(snapshot: ScreenSnapshot(displays: [makeDisplay()], windows: []), delegate: delegate)
        defer { controller.dismiss() }
        guard let other = controller.activeView else { return XCTFail("no active view") }
        // Same view is a no-op; a different view becomes active and reports its selection.
        controller.overlayViewDidBecomeActive(other)
        let second = ScreenshotOverlayView(frame: NSRect(x: 0, y: 0, width: 100, height: 100),
                                           display: makeDisplay(), windows: [], mainDisplayHeight: 100, ownPID: 1)
        second.selection = SelectionModel(bounds: second.display.localBounds,
                                          rect: CGRect(x: 5, y: 5, width: 20, height: 20))
        controller.overlayViewDidBecomeActive(second)
        XCTAssertTrue(controller.activeView === second)
        XCTAssertEqual(delegate.lastRect as? CGRect, CGRect(x: 5, y: 5, width: 20, height: 20))
        XCTAssertEqual(controller.currentSelection?.rect, CGRect(x: 5, y: 5, width: 20, height: 20))
    }
}

@MainActor
final class ScreenshotDrawingSmokeTests: XCTestCase {
    private func makeDisplay() -> CapturedDisplay {
        let size = CGSize(width: 400, height: 300)
        let descriptor = DisplayDescriptor(id: 1, quartzFrame: CGRect(origin: .zero, size: size),
                                           cocoaFrame: CGRect(origin: .zero, size: size))
        let provider = CGDataProvider(data: Data([UInt8](repeating: 120, count: Int(size.width * size.height * 4))) as CFData)!
        let image = CGImage(width: Int(size.width), height: Int(size.height), bitsPerComponent: 8, bitsPerPixel: 32,
                            bytesPerRow: Int(size.width) * 4, space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
        return CapturedDisplay(descriptor: descriptor, image: image)
    }

    func testFullDrawPipelineRendersWithoutCrashing() {
        _ = NSApplication.shared
        let view = ScreenshotOverlayView(frame: NSRect(x: 0, y: 0, width: 400, height: 300),
                                         display: makeDisplay(), windows: [], mainDisplayHeight: 300, ownPID: 1)
        view.selection = SelectionModel(bounds: view.display.localBounds,
                                        rect: CGRect(x: 50, y: 50, width: 200, height: 150))
        let annotations = [
            Annotation(geometry: .rectangle(CGRect(x: 10, y: 10, width: 40, height: 30)), style: .default),
            Annotation(geometry: .ellipse(CGRect(x: 60, y: 10, width: 40, height: 30)), style: .default),
            Annotation(geometry: .arrow(ArrowGeometry(start: CGPoint(x: 10, y: 80), end: CGPoint(x: 90, y: 100))), style: .default),
            Annotation(geometry: .pen([CGPoint(x: 10, y: 120), CGPoint(x: 60, y: 130), CGPoint(x: 90, y: 120)]), style: .default),
            Annotation(geometry: .text(TextGeometry(frame: CGRect(x: 100, y: 60, width: 80, height: 20), text: "测试")), style: .default),
            Annotation(geometry: .mosaic(CGRect(x: 100, y: 90, width: 60, height: 40)), style: .default),
        ]
        view.editor = view.editor.withHistory(AnnotationHistory(current: annotations))
        view.editor = view.editor.selectingTool(.rectangle)
        view.editor = view.editor.beginShape(at: CGPoint(x: 20, y: 20))
        view.editor = view.editor.updateShape(to: CGPoint(x: 50, y: 50))
        view.layoutToolbar()
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
            return XCTFail("no bitmap rep")
        }
        view.cacheDisplay(in: view.bounds, to: rep)
        // bitmapImageRepForCachingDisplay scales pixels by the screen's backingScaleFactor;
        // the point size always matches the view bounds.
        XCTAssertEqual(rep.size, view.bounds.size)
        view.discardTextField()
    }

    func testErrorDescriptionsArePresentForEveryCase() {
        let errors: [ScreenshotError] = [.captureFailed, .imageEncodingFailed, .clipboardImageMissing,
                                         .clipboardWriteFailed, .saveFailed, .pinLimitExceeded, .sessionAlreadyActive]
        for error in errors {
            let description = error.errorDescription
            XCTAssertNotNil(description)
            XCTAssertFalse(description!.isEmpty)
            XCTAssertFalse(description!.hasPrefix("screenshot.error"), "missing localization for \(error)")
        }
        XCTAssertNotNil(ActionError.screenshotUnavailable.errorDescription)
    }
}
