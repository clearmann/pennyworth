import AppKit

/// Loads a clipboard image at its original resolution.
/// ClipboardMonitor's 512px thumbnail scaling must never apply here.
struct ClipboardImageLoader {
    let pasteboard: NSPasteboard

    init(pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
    }

    func loadImage() throws -> RenderedScreenshot {
        guard let image = NSImage(pasteboard: pasteboard) else {
            throw ScreenshotError.clipboardImageMissing
        }
        let bitmap = image.representations
            .compactMap { $0 as? NSBitmapImageRep }
            .max { $0.pixelsWide * $0.pixelsHigh < $1.pixelsWide * $1.pixelsHigh }
        guard let cgImage = bitmap?.cgImage ?? image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw ScreenshotError.clipboardImageMissing
        }
        let pointSize = image.size.width > 0 && image.size.height > 0
            ? image.size
            : NSSize(width: cgImage.width, height: cgImage.height)
        return RenderedScreenshot(cgImage: cgImage, pointSize: pointSize)
    }
}
