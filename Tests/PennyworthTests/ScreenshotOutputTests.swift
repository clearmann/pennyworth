import XCTest
@testable import Pennyworth

@MainActor
final class ScreenshotOutputTests: XCTestCase {
    private var pasteboard: NSPasteboard!
    private var manager: PinnedImageManager!

    override func setUp() {
        super.setUp()
        pasteboard = NSPasteboard.withUniqueName()
        manager = PinnedImageManager()
    }

    override func tearDown() {
        manager.closeAll()
        manager = nil
        pasteboard.releaseGlobally()
        pasteboard = nil
        super.tearDown()
    }

    private func makeScreenshot(width: Int = 64, height: Int = 32) -> RenderedScreenshot {
        let provider = CGDataProvider(data: Data([UInt8](repeating: 200, count: width * height * 4)) as CFData)!
        let image = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                            space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
        return RenderedScreenshot(cgImage: image, pointSize: CGSize(width: width / 2, height: height / 2))
    }

    func testCopyWritesPNGAndTIFFAtOriginalResolution() throws {
        let output = ScreenshotOutputHandler(pasteboard: pasteboard, pinnedImageManager: manager)
        try output.copy(makeScreenshot())
        let pngData = pasteboard.data(forType: .png)
        XCTAssertNotNil(pngData)
        XCTAssertNotNil(pasteboard.data(forType: .tiff))
        let rep = NSBitmapImageRep(data: pngData!)
        XCTAssertEqual(rep?.pixelsWide, 64)
        XCTAssertEqual(rep?.pixelsHigh, 32)
    }

    func testPinClipboardWithoutImageThrows() {
        let output = ScreenshotOutputHandler(pasteboard: pasteboard, pinnedImageManager: manager)
        XCTAssertThrowsError(try output.pinClipboard()) { error in
            XCTAssertEqual(error as? ScreenshotError, .clipboardImageMissing)
        }
    }

    func testPinClipboardPinsOriginalResolutionImage() throws {
        pasteboard.clearContents()
        let data = try makeScreenshot().pngData()
        pasteboard.setData(data, forType: .png)
        let output = ScreenshotOutputHandler(pasteboard: pasteboard, pinnedImageManager: manager)
        try output.pinClipboard()
        XCTAssertEqual(manager.windows.count, 1)
        let pinned = try XCTUnwrap(manager.windows.first)
        // Clipboard PNGs carry no DPI metadata, so 1pt == 1px; pixels must not be rescaled.
        XCTAssertEqual(pinned.frame.size, CGSize(width: 64, height: 32))
    }

    func testClipboardImageLoaderKeepsOriginalResolution() throws {
        pasteboard.clearContents()
        pasteboard.setData(try makeScreenshot(width: 64, height: 32).pngData(), forType: .png)
        let loaded = try ClipboardImageLoader(pasteboard: pasteboard).loadImage()
        XCTAssertEqual(loaded.cgImage.width, 64)
        XCTAssertEqual(loaded.cgImage.height, 32)
        XCTAssertLessThanOrEqual(loaded.pointSize.width, 64, "never upscaled; crucially not downscaled to 512 thumbnails either")
    }
}
