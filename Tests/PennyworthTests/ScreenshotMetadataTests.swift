import XCTest
@testable import Pennyworth

@MainActor
final class ScreenshotMetadataTests: XCTestCase {
    func testDisplaysMatchesNSScreenAndCGDisplayBounds() {
        let displays = ScreenWindowMetadata.displays()
        XCTAssertFalse(displays.isEmpty)
        for display in displays {
            XCTAssertEqual(display.quartzFrame, CGDisplayBounds(display.id))
            let screen = NSScreen.screens.first {
                ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == display.id
            }
            XCTAssertEqual(display.cocoaFrame, screen?.frame)
        }
    }

    func testCurrentWindowsParsesRealWindowList() {
        // CGWindowList metadata requires no screen-recording permission and has no side effects.
        let windows = ScreenWindowMetadata.currentWindows()
        XCTAssertFalse(windows.isEmpty)
        for window in windows {
            XCTAssertGreaterThan(window.quartzBounds.width, 0)
            XCTAssertGreaterThan(window.quartzBounds.height, 0)
            XCTAssertGreaterThanOrEqual(window.alpha, 0)
        }
    }

    func testMouseMovedHighlightsEligibleWindow() {
        _ = NSApplication.shared
        let size = CGSize(width: 800, height: 600)
        let descriptor = DisplayDescriptor(id: 1, quartzFrame: CGRect(origin: .zero, size: size),
                                           cocoaFrame: CGRect(origin: .zero, size: size))
        let provider = CGDataProvider(data: Data([UInt8](repeating: 100, count: Int(size.width * size.height * 4))) as CFData)!
        let image = CGImage(width: Int(size.width), height: Int(size.height), bitsPerComponent: 8, bitsPerPixel: 32,
                            bytesPerRow: Int(size.width) * 4, space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
        let display = CapturedDisplay(descriptor: descriptor, image: image)
        // Quartz (50,50,200,200) with main height 600 → local (50,350,200,200).
        let window = WindowDescriptor(id: 7, ownerPID: 2, layer: 0,
                                      quartzBounds: CGRect(x: 50, y: 50, width: 200, height: 200),
                                      alpha: 1, isOnscreen: true, sharingState: 1)
        let view = ScreenshotOverlayView(frame: NSRect(origin: .zero, size: size), display: display,
                                         windows: [window], mainDisplayHeight: 600, ownPID: 1)
        func move(to point: CGPoint) {
            let event = NSEvent.mouseEvent(with: .mouseMoved, location: point, modifierFlags: [], timestamp: 0,
                                           windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
            view.mouseMoved(with: event)
        }
        move(to: CGPoint(x: 100, y: 400))
        XCTAssertEqual(view.highlightedWindow?.windowID, 7)
        move(to: CGPoint(x: 700, y: 50))
        XCTAssertNil(view.highlightedWindow)
    }
}

@MainActor
final class ScreenshotSaveTests: XCTestCase {
    func testWritePNGAtomicallyWritesDecodableFile() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let provider = CGDataProvider(data: Data([UInt8](repeating: 160, count: 8 * 6 * 4)) as CFData)!
        let image = CGImage(width: 8, height: 6, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: 32,
                            space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
        let screenshot = RenderedScreenshot(cgImage: image, pointSize: CGSize(width: 8, height: 6))
        let url = directory.appendingPathComponent("shot.png")
        try ScreenshotOutputHandler.writePNG(screenshot, to: url)
        let rep = NSBitmapImageRep(data: try Data(contentsOf: url))
        XCTAssertEqual(rep?.pixelsWide, 8)
        XCTAssertEqual(rep?.pixelsHigh, 6)
    }

    func testDefaultFileNameFormat() {
        let name = ScreenshotOutputHandler.defaultFileName()
        XCTAssertTrue(name.hasPrefix("Pennyworth "))
        XCTAssertTrue(name.hasSuffix(".png"))
        XCTAssertFalse(name.contains(":"), "file names must not contain colons")
    }

    func testPixelSizeAndCancelOperation() {
        let provider = CGDataProvider(data: Data([UInt8](repeating: 90, count: 8 * 6 * 4)) as CFData)!
        let image = CGImage(width: 8, height: 6, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: 32,
                            space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
        let screenshot = RenderedScreenshot(cgImage: image, pointSize: CGSize(width: 4, height: 3))
        XCTAssertEqual(screenshot.pixelSize, CGSize(width: 8, height: 6))

        let view = ScreenshotOverlayView(frame: NSRect(x: 0, y: 0, width: 100, height: 100),
                                         display: CapturedDisplay(
                                            descriptor: DisplayDescriptor(id: 1, quartzFrame: CGRect(x: 0, y: 0, width: 100, height: 100),
                                                                          cocoaFrame: CGRect(x: 0, y: 0, width: 100, height: 100)),
                                            image: image),
                                         windows: [], mainDisplayHeight: 100, ownPID: 1)
        let spy = CancelSpy()
        view.delegate = spy
        view.cancelOperation(nil)
        XCTAssertEqual(spy.cancelCount, 1)
    }

    private final class CancelSpy: ScreenshotOverlayViewDelegate {
        var cancelCount = 0
        func overlayViewDidCancel(_ view: ScreenshotOverlayView) { cancelCount += 1 }
        func overlayViewDidConfirm(_ view: ScreenshotOverlayView) {}
        func overlayView(_ view: ScreenshotOverlayView, didChangeSelection rect: CGRect?) {}
        func overlayViewDidBecomeActive(_ view: ScreenshotOverlayView) {}
        func overlayViewDidRequestSave(_ view: ScreenshotOverlayView) {}
        func overlayViewDidRequestPin(_ view: ScreenshotOverlayView) {}
    }
}
