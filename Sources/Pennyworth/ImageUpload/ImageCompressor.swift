import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

struct CompressedUploadData: Equatable, Sendable {
    let data: Data
    let fileExtension: String
    let mimeType: String
    let didCompress: Bool
}

enum ImageCompressor {
    private static let compressibleExtensions: Set<String> = [
        "jpg", "jpeg", "png", "tiff", "tif", "bmp", "heic", "heif",
    ]

    /// Compresses static raster images according to `qualityFactor` (10...100).
    /// - Skips compression when `qualityFactor >= 100`.
    /// - Skips GIF animations, SVGs, and non-image files.
    /// - Preserves alpha-transparent PNGs without converting to opaque JPEG.
    /// - Keeps original bytes if re-encoding does not reduce file size.
    static func compress(
        data: Data,
        fileExtension: String,
        mimeType: String,
        qualityFactor: Int
    ) -> CompressedUploadData {
        let normalizedExt = fileExtension.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
        let unchanged = CompressedUploadData(
            data: data,
            fileExtension: normalizedExt,
            mimeType: mimeType,
            didCompress: false
        )

        guard qualityFactor < 100, !data.isEmpty else {
            return unchanged
        }
        guard !isGIF(data: data, fileExtension: normalizedExt),
              compressibleExtensions.contains(normalizedExt) else {
            return unchanged
        }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) == 1,
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            return unchanged
        }

        let clampedQuality = Double(max(10, min(99, qualityFactor))) / 100.0
        if hasTransparentPixels(cgImage) {
            return unchanged
        }

        guard let encoded = encodeAsJPEG(cgImage: cgImage, quality: clampedQuality),
              encoded.count < data.count else {
            return unchanged
        }

        return CompressedUploadData(
            data: encoded,
            fileExtension: "jpg",
            mimeType: "image/jpeg",
            didCompress: true
        )
    }

    static func makeThumbnail(from data: Data, maxPixelSize: Int = 64) -> Data? {
        guard !data.isEmpty,
              let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            return nil
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(destination, thumbnail, nil)
        guard CGImageDestinationFinalize(destination) else {
            return nil
        }
        return output as Data
    }

    private static func isGIF(data: Data, fileExtension: String) -> Bool {
        if fileExtension == "gif" { return true }
        guard data.count >= 6 else { return false }
        let prefix = data.prefix(6)
        return prefix == Data("GIF87a".utf8) || prefix == Data("GIF89a".utf8)
    }

    private static func encodeAsJPEG(cgImage: CGImage, quality: Double) -> Data? {
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) else {
            return nil
        }
        let properties: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: quality,
        ]
        CGImageDestinationAddImage(destination, cgImage, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            return nil
        }
        return output as Data
    }

    /// Checks whether an image actually contains any semi-transparent or transparent pixels.
    /// Screenshots captured on macOS often report `premultipliedLast` / `last` even when fully opaque,
    /// so checking pixel alpha avoids falsely skipping opaque PNG screenshots.
    private static func hasTransparentPixels(_ image: CGImage) -> Bool {
        switch image.alphaInfo {
        case .none, .noneSkipFirst, .noneSkipLast:
            return false
        default:
            break
        }
        let width = min(image.width, 512)
        let height = min(image.height, 512)
        guard width > 0, height > 0 else { return false }

        let bytesPerRow = width * 4
        var buffer = [UInt8](repeating: 0, count: bytesPerRow * height)
        guard let context = CGContext(
            data: &buffer,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return true
        }
        context.setBlendMode(.copy)
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        var index = 3
        while index < buffer.count {
            if buffer[index] < 255 {
                return true
            }
            index += 4
        }
        return false
    }
}
