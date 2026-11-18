import CoreGraphics
import XCTest
@testable import Pennyworth

final class AnnotationRendererTests: XCTestCase {
    private func makeContext(width: Int = 100, height: Int = 100) -> CGContext {
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context
    }

    private func image(of context: CGContext) -> CGImage { context.makeImage()! }

    private func pixel(in image: CGImage, x: Int, y: Int) -> (r: Int, g: Int, b: Int) {
        let data = image.dataProvider!.data!
        let bytes = CFDataGetBytePtr(data)!
        // CGContext image rows are bottom-up in memory? No: row 0 is the context's top edge.
        // We sample with y measured from the top: convert AppKit y to row index.
        let row = image.height - 1 - y
        let offset = row * image.bytesPerRow + x * 4
        return (Int(bytes[offset]), Int(bytes[offset + 1]), Int(bytes[offset + 2]))
    }

    private func isReddish(_ pixel: (r: Int, g: Int, b: Int)) -> Bool {
        pixel.r > 180 && pixel.g < 110 && pixel.b < 110
    }

    private func isWhitish(_ pixel: (r: Int, g: Int, b: Int)) -> Bool {
        pixel.r > 240 && pixel.g > 240 && pixel.b > 240
    }

    private func annotation(_ geometry: AnnotationGeometry,
                            style: AnnotationStyle = .default) -> Annotation {
        Annotation(geometry: geometry, style: style)
    }

    private func render(_ annotations: [Annotation], mosaicSource: CGImage? = nil) -> CGImage {
        let context = makeContext()
        AnnotationRenderer.draw(annotations: annotations, mosaicSource: mosaicSource,
                                scaleX: 1, scaleY: 1, in: context)
        return image(of: context)
    }

    func testRectangleStrokesEdgesOnly() {
        let image = render([annotation(.rectangle(CGRect(x: 10, y: 10, width: 50, height: 50)))])
        XCTAssertTrue(isReddish(pixel(in: image, x: 30, y: 10)))
        XCTAssertTrue(isReddish(pixel(in: image, x: 10, y: 30)))
        XCTAssertTrue(isWhitish(pixel(in: image, x: 30, y: 30)))
        XCTAssertTrue(isWhitish(pixel(in: image, x: 80, y: 80)))
    }

    func testEllipseExcludesCorners() {
        let image = render([annotation(.ellipse(CGRect(x: 10, y: 10, width: 60, height: 40)))])
        XCTAssertTrue(isReddish(pixel(in: image, x: 40, y: 10)))
        XCTAssertTrue(isWhitish(pixel(in: image, x: 12, y: 12)))
        XCTAssertTrue(isWhitish(pixel(in: image, x: 40, y: 30)))
    }

    func testArrowHeadIsAtEndPoint() {
        let arrow = ArrowGeometry(start: CGPoint(x: 10, y: 50), end: CGPoint(x: 80, y: 50))
        let image = render([annotation(.arrow(arrow))])
        XCTAssertTrue(isReddish(pixel(in: image, x: 50, y: 50)))
        XCTAssertTrue(isReddish(pixel(in: image, x: 79, y: 50)))
        // Wings fan out backwards from the tip: scan the region above the line near the end.
        var wingInk = false
        for x in 70..<80 where !wingInk {
            for y in 51..<56 where isReddish(pixel(in: image, x: x, y: y)) {
                wingInk = true
                break
            }
        }
        XCTAssertTrue(wingInk, "arrow head wings must fan out above the shaft near the tip")
        XCTAssertTrue(isWhitish(pixel(in: image, x: 20, y: 54)))
        XCTAssertTrue(isWhitish(pixel(in: image, x: 90, y: 50)))
    }

    func testPenDrawsConnectedPolyline() {
        let image = render([annotation(.pen([CGPoint(x: 10, y: 10), CGPoint(x: 50, y: 50), CGPoint(x: 80, y: 50)]))])
        XCTAssertTrue(isReddish(pixel(in: image, x: 30, y: 30)))
        XCTAssertTrue(isReddish(pixel(in: image, x: 65, y: 50)))
        XCTAssertTrue(isWhitish(pixel(in: image, x: 30, y: 60)))
    }

    func testTextLeavesNonWhitePixelsInsideFrame() {
        let geometry = TextGeometry(frame: CGRect(x: 10, y: 10, width: 80, height: 20), text: "Hi")
        let image = render([annotation(.text(geometry))])
        var foundInk = false
        for x in 10..<90 where !foundInk {
            for y in 10..<30 where !isWhitish(pixel(in: image, x: x, y: y)) {
                foundInk = true
                break
            }
        }
        XCTAssertTrue(foundInk)
        XCTAssertTrue(isWhitish(pixel(in: image, x: 95, y: 95)))
    }

    func testAlphaBlendsWithBackground() {
        let style = AnnotationStyle(color: RGBAColor(red: 1, green: 0, blue: 0, alpha: 0.5),
                                    lineWidth: 6, fontSize: 16, mosaicBlockSize: 12)
        let image = render([annotation(.rectangle(CGRect(x: 10, y: 10, width: 50, height: 50)), style: style)])
        let edge = pixel(in: image, x: 30, y: 10)
        XCTAssertTrue(edge.r > 200)
        XCTAssertTrue(edge.g > 80 && edge.g < 180, "50% red over white must be pink, got \(edge)")
    }

    // MARK: - Mosaic

    /// 4×4px quadrant source: top-left red, top-right green, bottom-left blue, bottom-right white.
    private func makeQuadrantSource() -> CGImage {
        let red: [UInt8] = [255, 0, 0, 255]
        let green: [UInt8] = [0, 255, 0, 255]
        let blue: [UInt8] = [0, 0, 255, 255]
        let white: [UInt8] = [255, 255, 255, 255]
        var pixels: [UInt8] = []
        for _ in 0..<2 { pixels.append(contentsOf: red + red + green + green) }
        for _ in 0..<2 { pixels.append(contentsOf: blue + blue + white + white) }
        let provider = CGDataProvider(data: Data(pixels) as CFData)!
        return CGImage(width: 4, height: 4, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: 16,
                       space: CGColorSpaceCreateDeviceRGB(),
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
    }

    func testMosaicPixelatesBottomLeftQuadrantToSingleBlockColor() {
        // Selection is 4×4pt with a 4×4px source (scale 1). Mosaic the AppKit bottom-left quadrant.
        let context = makeContext(width: 4, height: 4)
        AnnotationRenderer.draw(annotations: [annotation(.mosaic(CGRect(x: 0, y: 0, width: 2, height: 2)))],
                                mosaicSource: makeQuadrantSource(), scaleX: 1, scaleY: 1, in: context)
        let image = image(of: context)
        let a = pixel(in: image, x: 0, y: 0)
        let b = pixel(in: image, x: 1, y: 1)
        XCTAssertEqual(a.r, b.r)
        XCTAssertEqual(a.g, b.g)
        XCTAssertEqual(a.b, b.b)
        XCTAssertTrue(a.b > 200 && a.r < 60, "bottom-left quadrant is blue, got \(a)")
        // The renderer draws annotations only: pixels outside the mosaic rect keep the
        // context's original white background (clipping must not bleed outside the rect).
        XCTAssertTrue(isWhitish(pixel(in: image, x: 0, y: 3)))
        XCTAssertTrue(isWhitish(pixel(in: image, x: 3, y: 0)))
    }
}
