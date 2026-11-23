@testable import Pennyworth
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import XCTest

final class ImageCompressorTests: XCTestCase {
    func testQuality100ReturnsOriginalBytesUnchanged() throws {
        let png = try makeTestPNG(width: 200, height: 200, transparentPixel: false)
        let result = ImageCompressor.compress(
            data: png,
            fileExtension: "png",
            mimeType: "image/png",
            qualityFactor: 100
        )
        XCTAssertFalse(result.didCompress)
        XCTAssertEqual(result.data, png)
        XCTAssertEqual(result.fileExtension, "png")
        XCTAssertEqual(result.mimeType, "image/png")
    }

    func testOpaquePNGCompressesToSmallerJPEG() throws {
        let png = try makeTestPNG(width: 320, height: 240, transparentPixel: false)
        let result = ImageCompressor.compress(
            data: png,
            fileExtension: "png",
            mimeType: "image/png",
            qualityFactor: 60
        )
        XCTAssertTrue(result.didCompress)
        XCTAssertLessThan(result.data.count, png.count)
        XCTAssertEqual(result.fileExtension, "jpg")
        XCTAssertEqual(result.mimeType, "image/jpeg")
    }

    func testTransparentPNGSkipsLossyJPEGConversion() throws {
        let png = try makeTestPNG(width: 160, height: 160, transparentPixel: true)
        let result = ImageCompressor.compress(
            data: png,
            fileExtension: "png",
            mimeType: "image/png",
            qualityFactor: 50
        )
        XCTAssertFalse(result.didCompress)
        XCTAssertEqual(result.data, png)
        XCTAssertEqual(result.fileExtension, "png")
    }

    func testSkipsGIFAndNonImageFiles() {
        let gifBytes = Data("GIF89a\u{01}\u{00}\u{01}\u{00}\u{00}\u{00}\u{00};".utf8)
        let gifResult = ImageCompressor.compress(
            data: gifBytes,
            fileExtension: "gif",
            mimeType: "image/gif",
            qualityFactor: 50
        )
        XCTAssertFalse(gifResult.didCompress)
        XCTAssertEqual(gifResult.data, gifBytes)

        let textBytes = Data("hello pennyworth".utf8)
        let textResult = ImageCompressor.compress(
            data: textBytes,
            fileExtension: "txt",
            mimeType: "text/plain",
            qualityFactor: 50
        )
        XCTAssertFalse(textResult.didCompress)
        XCTAssertEqual(textResult.data, textBytes)
    }

    func testMakeThumbnailProducesSmallPNG() throws {
        let png = try makeTestPNG(width: 300, height: 200, transparentPixel: false)
        let thumbData = try XCTUnwrap(ImageCompressor.makeThumbnail(from: png, maxPixelSize: 48))
        let source = try XCTUnwrap(CGImageSourceCreateWithData(thumbData as CFData, nil))
        let cgImage = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        XCTAssertLessThanOrEqual(max(cgImage.width, cgImage.height), 48)
    }

    private func makeTestPNG(width: Int, height: Int, transparentPixel: Bool) throws -> Data {
        let bytesPerRow = width * 4
        var pixels = [UInt8](repeating: 255, count: bytesPerRow * height)
        for y in 0..<height {
            for x in 0..<width {
                let offset = y * bytesPerRow + x * 4
                // Smooth photographic-like gradients with subtle variation (PNG is large, JPEG compresses well)
                let fx = Double(x) / Double(max(1, width - 1))
                let fy = Double(y) / Double(max(1, height - 1))
                let wave = sin(fx * 12.0) * cos(fy * 10.0) * 40.0
                pixels[offset] = UInt8(max(0, min(255, Int(fx * 200.0 + wave + 25.0))))
                pixels[offset + 1] = UInt8(max(0, min(255, Int(fy * 190.0 - wave + 30.0))))
                pixels[offset + 2] = UInt8(max(0, min(255, Int(((fx + fy) * 110.0) + sin((fx + fy) * 18.0) * 20.0 + 15.0))))
                pixels[offset + 3] = (transparentPixel && x < 20 && y < 20) ? 0 : 255
            }
        }
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = try XCTUnwrap(CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        let image = try XCTUnwrap(context.makeImage())
        let output = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return output as Data
    }
}
