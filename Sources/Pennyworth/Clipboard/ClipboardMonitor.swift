import AppKit

final class ClipboardMonitor {
    static let maxImageDimension: CGFloat = 512
    private static let concealedTypes: Set<NSPasteboard.PasteboardType> = [
        NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType"),
        NSPasteboard.PasteboardType("org.nspasteboard.TransientType"),
        NSPasteboard.PasteboardType("com.agilebits.onepassword")
    ]

    private let pasteboard: NSPasteboard
    private var lastChangeCount: Int

    init(pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
        lastChangeCount = pasteboard.changeCount
    }

    func markCurrentChangeAsSeen() {
        lastChangeCount = pasteboard.changeCount
    }

    func checkPasteboard() -> ClipboardItem? {
        guard pasteboard.changeCount != lastChangeCount else { return nil }
        lastChangeCount = pasteboard.changeCount
        guard Set(pasteboard.types ?? []).isDisjoint(with: Self.concealedTypes) else { return nil }
        let timestamp = Date()
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL],
           let url = urls.first, url.isFileURL {
            return ClipboardItem(content: .file(url), timestamp: timestamp)
        }
        if let image = NSImage(pasteboard: pasteboard) {
            let scaled = image.scaled(maxDimension: Self.maxImageDimension)
            return ClipboardItem(content: .image(scaled, size: scaled.size), timestamp: timestamp)
        }
        guard let text = pasteboard.string(forType: .string),
              text.utf8.count <= 1_024 * 1_024 else { return nil }
        return ClipboardItem(content: .text(text), timestamp: timestamp)
    }
}

private extension NSImage {
    func scaled(maxDimension: CGFloat) -> NSImage {
        let longestSide = max(size.width, size.height)
        guard longestSide > maxDimension, longestSide > 0 else { return self }
        let scale = maxDimension / longestSide
        let targetSize = NSSize(width: size.width * scale, height: size.height * scale)
        let result = NSImage(size: targetSize)
        result.lockFocus()
        draw(in: NSRect(origin: .zero, size: targetSize), from: .zero, operation: .copy, fraction: 1)
        result.unlockFocus()
        return result
    }
}
