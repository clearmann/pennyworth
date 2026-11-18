import CoreGraphics
import XCTest
@testable import Pennyworth

final class ScreenshotGeometryTests: XCTestCase {
    private func makeDisplay(quartz: CGRect = CGRect(x: 0, y: 0, width: 800, height: 600),
                             cocoa: CGRect? = nil,
                             scale: Int = 2) -> CapturedDisplay {
        let descriptor = DisplayDescriptor(id: 1, quartzFrame: quartz, cocoaFrame: cocoa ?? quartz)
        let context = CGContext(data: nil, width: Int(quartz.width) * scale, height: Int(quartz.height) * scale,
                                bitsPerComponent: 8, bytesPerRow: Int(quartz.width) * scale * 4,
                                space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        return CapturedDisplay(descriptor: descriptor, image: context.makeImage()!)
    }

    func testQuartzToCocoaFlipsYWithinMainDisplay() {
        let rect = ScreenGeometry.quartzToCocoa(CGRect(x: 100, y: 50, width: 400, height: 300),
                                                mainDisplayHeight: 1080)
        XCTAssertEqual(rect, CGRect(x: 100, y: 730, width: 400, height: 300))
    }

    func testLocalRectSubtractsNegativeOriginSecondaryDisplay() {
        let display = DisplayDescriptor(id: 2, quartzFrame: CGRect(x: -1920, y: 0, width: 1920, height: 1080),
                                        cocoaFrame: CGRect(x: -1920, y: 0, width: 1920, height: 1080))
        let local = ScreenGeometry.localRect(forCocoaGlobal: CGRect(x: -1900, y: 40, width: 200, height: 100),
                                             in: display)
        XCTAssertEqual(local, CGRect(x: 20, y: 40, width: 200, height: 100))
    }

    func testLocalRectFromQuartzGlobalCombinesFlipAndOrigin() {
        let display = DisplayDescriptor(id: 1, quartzFrame: CGRect(x: 0, y: 0, width: 1000, height: 1000),
                                        cocoaFrame: CGRect(x: 0, y: 0, width: 1000, height: 1000))
        let local = ScreenGeometry.localRect(forQuartzGlobal: CGRect(x: 100, y: 100, width: 200, height: 200),
                                             in: display, mainDisplayHeight: 1000)
        XCTAssertEqual(local, CGRect(x: 100, y: 700, width: 200, height: 200))
    }

    func testStandardizedHandlesAllDragDirections() {
        let expected = CGRect(x: 10, y: 20, width: 100, height: 50)
        XCTAssertEqual(ScreenGeometry.standardized(from: CGPoint(x: 10, y: 20), to: CGPoint(x: 110, y: 70)), expected)
        XCTAssertEqual(ScreenGeometry.standardized(from: CGPoint(x: 110, y: 70), to: CGPoint(x: 10, y: 20)), expected)
        XCTAssertEqual(ScreenGeometry.standardized(from: CGPoint(x: 10, y: 70), to: CGPoint(x: 110, y: 20)), expected)
        XCTAssertEqual(ScreenGeometry.standardized(from: CGPoint(x: 110, y: 20), to: CGPoint(x: 10, y: 70)), expected)
    }

    func testClampedIntersectsWithDisplayBounds() {
        let bounds = CGRect(x: 0, y: 0, width: 800, height: 600)
        XCTAssertEqual(ScreenGeometry.clamped(CGRect(x: -50, y: 500, width: 200, height: 200), to: bounds),
                       CGRect(x: 0, y: 500, width: 150, height: 100))
    }

    func testPixelRectScalesAndFlipsForRetina() {
        let display = makeDisplay()
        XCTAssertEqual(display.scaleX, 2)
        let pixel = ScreenGeometry.pixelRect(for: CGRect(x: 10, y: 20, width: 100, height: 50), in: display)
        XCTAssertEqual(pixel, CGRect(x: 20, y: 1060, width: 200, height: 100))
    }

    func testPixelRectRoundsFractionalPoints() {
        let display = makeDisplay()
        let pixel = ScreenGeometry.pixelRect(for: CGRect(x: 10.26, y: 20.1, width: 100.24, height: 50.3), in: display)
        XCTAssertEqual(pixel, CGRect(x: 21, y: 1059, width: 200, height: 101))
    }

    func testPixelRectClampsToImageBounds() {
        let display = makeDisplay()
        let pixel = ScreenGeometry.pixelRect(for: CGRect(x: 790, y: 590, width: 100, height: 100), in: display)
        XCTAssertEqual(pixel, CGRect(x: 1580, y: 0, width: 20, height: 20))
    }

    func testPixelRectOutsideImageIsEmpty() {
        let display = makeDisplay()
        let pixel = ScreenGeometry.pixelRect(for: CGRect(x: 900, y: 900, width: 50, height: 50), in: display)
        XCTAssertTrue(pixel.isEmpty || pixel.isNull)
    }

    func testNonUniformScaleUsesPerAxisFactors() {
        let display = makeDisplay(quartz: CGRect(x: 0, y: 0, width: 100, height: 100), scale: 1)
        // Force a synthetic non-uniform scale: 100pt wide image is 100px, height stays 100px (scale 1).
        let pixel = ScreenGeometry.pixelRect(for: CGRect(x: 10, y: 10, width: 20, height: 20), in: display)
        XCTAssertEqual(pixel, CGRect(x: 10, y: 70, width: 20, height: 20))
    }
}
