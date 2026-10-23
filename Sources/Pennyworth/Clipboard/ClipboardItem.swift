import AppKit
import Foundation

/// One locally stored clipboard entry.
enum ClipboardContent: Equatable {
    case text(String)
    case image(NSImage, size: NSSize)
    case file(URL)
}

struct ClipboardItem: Identifiable, Equatable, Codable {
    let id: UUID
    let content: ClipboardContent
    let timestamp: Date

    init(id: UUID = UUID(), content: ClipboardContent, timestamp: Date) {
        self.id = id
        self.content = content
        self.timestamp = timestamp
    }

    var displayTitle: String {
        switch content {
        case .text(let value):
            let preview = value.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return preview.count > 60 ? String(preview.prefix(60)) + "…" : preview
        case .image(_, let size):
            return "Image: \(Int(size.width))×\(Int(size.height))"
        case .file(let url):
            return url.lastPathComponent
        }
    }

    var displaySubtitle: String {
        switch content {
        case .text(let value): return "\(value.count) 个字符 · \(timestamp.formatted(date: .abbreviated, time: .shortened))"
        case .image(_, let size): return "\(Int(size.width))×\(Int(size.height)) · \(timestamp.formatted(date: .abbreviated, time: .shortened))"
        case .file(let url): return url.path
        }
    }

    var storageByteCount: Int {
        switch content {
        case .text(let value): return value.utf8.count
        case .image(let image, _): return image.pngData?.count ?? 0
        case .file(let url): return url.path.utf8.count
        }
    }

    private enum CodingKeys: String, CodingKey {
        case id, timestamp, kind, text, filePath, imageData, imageWidth, imageHeight
    }

    private enum Kind: String, Codable {
        case text, image, file
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        let kind = try container.decode(Kind.self, forKey: .kind)
        switch kind {
        case .text:
            content = .text(try container.decode(String.self, forKey: .text))
        case .file:
            content = .file(URL(fileURLWithPath: try container.decode(String.self, forKey: .filePath)))
        case .image:
            let data = try container.decode(Data.self, forKey: .imageData)
            guard let image = NSImage(data: data) else {
                throw DecodingError.dataCorruptedError(forKey: .imageData, in: container,
                                                       debugDescription: "无法读取剪贴板图片")
            }
            let width = try container.decode(CGFloat.self, forKey: .imageWidth)
            let height = try container.decode(CGFloat.self, forKey: .imageHeight)
            content = .image(image, size: NSSize(width: width, height: height))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(timestamp, forKey: .timestamp)
        switch content {
        case .text(let value):
            try container.encode(Kind.text, forKey: .kind)
            try container.encode(value, forKey: .text)
        case .file(let url):
            try container.encode(Kind.file, forKey: .kind)
            try container.encode(url.path, forKey: .filePath)
        case .image(let image, let size):
            guard let data = image.pngData else {
                throw EncodingError.invalidValue(image, EncodingError.Context(codingPath: container.codingPath,
                                                                              debugDescription: "无法保存剪贴板图片"))
            }
            try container.encode(Kind.image, forKey: .kind)
            try container.encode(data, forKey: .imageData)
            try container.encode(size.width, forKey: .imageWidth)
            try container.encode(size.height, forKey: .imageHeight)
        }
    }
}

private extension NSImage {
    var pngData: Data? {
        guard let tiff = tiffRepresentation,
              let representation = NSBitmapImageRep(data: tiff) else { return nil }
        return representation.representation(using: .png, properties: [:])
    }
}
