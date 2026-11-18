import CoreGraphics
import XCTest
@testable import Pennyworth

final class ScreenshotCompositorTests: XCTestCase {
    /// A 4×4 image (2× scale of a 2×2pt display) with four distinct quadrant colors:
    /// top-left red, top-right green, bottom-left blue, bottom-right white (image coords, top-left origin).
    /// Raw pixel bytes avoid any color-management conversion during fixture creation.
    private func makeQuadrantDisplay() -> CapturedDisplay {
        let descriptor = DisplayDescriptor(id: 1, quartzFrame: CGRect(x: 0, y: 0, width: 2, height: 2),
                                           cocoaFrame: CGRect(x: 0, y: 0, width: 2, height: 2))
        let red: [UInt8] = [255, 0, 0, 255]
        let green: [UInt8] = [0, 255, 0, 255]
        let blue: [UInt8] = [0, 0, 255, 255]
        let white: [UInt8] = [255, 255, 255, 255]
        var pixels: [UInt8] = []
        for _ in 0..<2 { pixels.append(contentsOf: red + red + green + green) } // rows 0-1
        for _ in 0..<2 { pixels.append(contentsOf: blue + blue + white + white) } // rows 2-3
        let provider = CGDataProvider(data: Data(pixels) as CFData)!
        let image = CGImage(width: 4, height: 4, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: 16,
                            space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                            provider: provider, decode: nil, shouldInterpolate: false,
                            intent: .defaultIntent)!
        return CapturedDisplay(descriptor: descriptor, image: image)
    }

    private func color(at point: CGPoint, in image: CGImage) -> (r: Int, g: Int, b: Int)? {
        guard let data = image.dataProvider?.data, let bytes = CFDataGetBytePtr(data) else { return nil }
        let offset = Int(point.y) * image.bytesPerRow + Int(point.x) * 4
        return (Int(bytes[offset]), Int(bytes[offset + 1]), Int(bytes[offset + 2]))
    }

    func testCropProducesRetinaPixelSizeAndPointSize() throws {
        let display = makeQuadrantDisplay()
        let result = try ScreenshotCompositor.compose(display: display, selection: CGRect(x: 0, y: 0, width: 1, height: 1))
        XCTAssertEqual(result.cgImage.width, 2)
        XCTAssertEqual(result.cgImage.height, 2)
        XCTAssertEqual(result.pointSize, CGSize(width: 1, height: 1))
    }

    func testCropSelectsCorrectQuadrantInAppKitCoordinates() throws {
        let display = makeQuadrantDisplay()
        // AppKit bottom-left quadrant (0,0,1,1) is image bottom-left = blue.
        let bottomLeft = try ScreenshotCompositor.compose(display: display, selection: CGRect(x: 0, y: 0, width: 1, height: 1))
        let bottomLeftColor = color(at: CGPoint(x: 0, y: 0), in: bottomLeft.cgImage)
        XCTAssertEqual(bottomLeftColor?.b, 255)
        XCTAssertEqual(bottomLeftColor?.r, 0)
        // AppKit top-left quadrant (0,1,1,1) is image top-left = red.
        let topLeft = try ScreenshotCompositor.compose(display: display, selection: CGRect(x: 0, y: 1, width: 1, height: 1))
        let topLeftColor = color(at: CGPoint(x: 0, y: 0), in: topLeft.cgImage)
        XCTAssertEqual(topLeftColor?.r, 255)
        XCTAssertEqual(topLeftColor?.g, 0)
        // AppKit top-right quadrant (1,1,1,1) = green.
        let topRight = try ScreenshotCompositor.compose(display: display, selection: CGRect(x: 1, y: 1, width: 1, height: 1))
        XCTAssertEqual(color(at: CGPoint(x: 0, y: 0), in: topRight.cgImage)?.g, 255)
        // AppKit bottom-right quadrant (1,0,1,1) = white.
        let bottomRight = try ScreenshotCompositor.compose(display: display, selection: CGRect(x: 1, y: 0, width: 1, height: 1))
        let white = color(at: CGPoint(x: 0, y: 0), in: bottomRight.cgImage)
        XCTAssertEqual(white?.r, 255)
        XCTAssertEqual(white?.g, 255)
        XCTAssertEqual(white?.b, 255)
    }

    func testPNGDataRoundTripsWithIdenticalDimensions() throws {
        let display = makeQuadrantDisplay()
        let result = try ScreenshotCompositor.compose(display: display, selection: CGRect(x: 0, y: 0, width: 2, height: 2))
        let data = try result.pngData()
        let decoded = NSBitmapImageRep(data: data)
        XCTAssertEqual(decoded?.pixelsWide, 4)
        XCTAssertEqual(decoded?.pixelsHigh, 4)
    }

    func testEmptySelectionThrows() {
        let display = makeQuadrantDisplay()
        XCTAssertThrowsError(try ScreenshotCompositor.compose(display: display, selection: .zero))
        XCTAssertThrowsError(try ScreenshotCompositor.compose(display: display,
                                                              selection: CGRect(x: 50, y: 50, width: 10, height: 10)))
    }
}
