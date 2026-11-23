import AppKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

struct RawUploadInput: Equatable, Sendable {
    let data: Data
    let filenameWithoutExtension: String
    let fileExtension: String
    let mimeType: String

    var fullFilename: String {
        fileExtension.isEmpty ? filenameWithoutExtension : "\(filenameWithoutExtension).\(fileExtension)"
    }
}

enum UploadInputLoader {
    static let maxFileSizeBytes = 100 * 1024 * 1024
    static let maxFileSizeMB = 100

    private static let gifPasteboardType = NSPasteboard.PasteboardType("com.compuserve.gif")
    private static let jpegPasteboardType = NSPasteboard.PasteboardType("public.jpeg")

    static func loadFromFileURLs(_ urls: [URL]) throws -> [RawUploadInput] {
        guard !urls.isEmpty else {
            throw ImageUploadError.clipboardEmpty
        }
        return try urls.map { try loadSingleFile($0) }
    }

    static func loadSingleFile(_ url: URL) throws -> RawUploadInput {
        let standardized = url.standardizedFileURL
        let name = standardized.lastPathComponent
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: standardized.path, isDirectory: &isDirectory) else {
            throw ImageUploadError.unreadableFile(name)
        }
        if isDirectory.boolValue {
            throw ImageUploadError.directoryNotSupported(name)
        }
        let attributes = try? FileManager.default.attributesOfItem(atPath: standardized.path)
        if let size = attributes?[.size] as? NSNumber, size.intValue > maxFileSizeBytes {
            throw ImageUploadError.fileTooLarge(name, maxFileSizeMB)
        }
        let data: Data
        do {
            data = try Data(contentsOf: standardized)
        } catch {
            throw ImageUploadError.unreadableFile(name)
        }
        if data.count > maxFileSizeBytes {
            throw ImageUploadError.fileTooLarge(name, maxFileSizeMB)
        }
        let ext = standardized.pathExtension.lowercased()
        let baseName = standardized.deletingPathExtension().lastPathComponent
        let mime = mimeType(forExtension: ext)
        return RawUploadInput(
            data: data,
            filenameWithoutExtension: baseName,
            fileExtension: ext,
            mimeType: mime
        )
    }

    static func loadFromPasteboard(_ pasteboard: NSPasteboard, date: Date = Date()) throws -> [RawUploadInput] {
        let fileURLs = extractFileURLs(from: pasteboard)
        if !fileURLs.isEmpty {
            return try loadFromFileURLs(fileURLs)
        }

        if let gifData = pasteboard.data(forType: gifPasteboardType), !gifData.isEmpty {
            return [RawUploadInput(
                data: gifData,
                filenameWithoutExtension: defaultClipboardFilename(date: date),
                fileExtension: "gif",
                mimeType: "image/gif"
            )]
        }

        if let pngData = pasteboard.data(forType: .png), !pngData.isEmpty {
            return [RawUploadInput(
                data: pngData,
                filenameWithoutExtension: defaultClipboardFilename(date: date),
                fileExtension: "png",
                mimeType: "image/png"
            )]
        }

        if let jpegData = pasteboard.data(forType: jpegPasteboardType), !jpegData.isEmpty {
            return [RawUploadInput(
                data: jpegData,
                filenameWithoutExtension: defaultClipboardFilename(date: date),
                fileExtension: "jpg",
                mimeType: "image/jpeg"
            )]
        }

        if let tiffData = pasteboard.data(forType: .tiff), !tiffData.isEmpty,
           let pngData = convertImageDataToPNG(tiffData) {
            return [RawUploadInput(
                data: pngData,
                filenameWithoutExtension: defaultClipboardFilename(date: date),
                fileExtension: "png",
                mimeType: "image/png"
            )]
        }

        if let image = NSImage(pasteboard: pasteboard),
           let tiff = image.tiffRepresentation,
           let pngData = convertImageDataToPNG(tiff) {
            return [RawUploadInput(
                data: pngData,
                filenameWithoutExtension: defaultClipboardFilename(date: date),
                fileExtension: "png",
                mimeType: "image/png"
            )]
        }

        throw ImageUploadError.clipboardEmpty
    }

    static func mimeType(forExtension ext: String) -> String {
        let cleaned = ext.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
        guard !cleaned.isEmpty else { return "application/octet-stream" }
        if let utType = UTType(filenameExtension: cleaned), let mime = utType.preferredMIMEType {
            return mime
        }
        return "application/octet-stream"
    }

    private static func extractFileURLs(from pasteboard: NSPasteboard) -> [URL] {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [
            .urlReadingFileURLsOnly: true,
        ]
        if let objects = pasteboard.readObjects(forClasses: [NSURL.self], options: options) as? [URL],
           !objects.isEmpty {
            return objects.filter(\.isFileURL)
        }
        if let items = pasteboard.pasteboardItems {
            let urls = items.compactMap { item -> URL? in
                guard let raw = item.string(forType: .fileURL),
                      let url = URL(string: raw),
                      url.isFileURL else {
                    return nil
                }
                return url
            }
            if !urls.isEmpty { return urls }
        }
        return []
    }

    private static func convertImageDataToPNG(_ data: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            return nil
        }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(destination, cgImage, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }

    private static func defaultClipboardFilename(date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return "uPic-\(formatter.string(from: date))"
    }
}
