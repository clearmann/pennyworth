import AppKit

enum ScreenshotSaveResult: Equatable {
    case saved(URL)
    case cancelled
}

@MainActor protocol ScreenshotOutputHandling {
    func copy(_ screenshot: RenderedScreenshot) throws
    func save(_ screenshot: RenderedScreenshot) async throws -> ScreenshotSaveResult
    func pin(_ screenshot: RenderedScreenshot) throws
    func pinClipboard() throws
}

@MainActor final class ScreenshotOutputHandler: ScreenshotOutputHandling {
    private let pasteboard: NSPasteboard
    private let imageLoader: ClipboardImageLoader
    private let pinnedImageManager: PinnedImageManager

    init(pasteboard: NSPasteboard = .general,
         imageLoader: ClipboardImageLoader? = nil,
         pinnedImageManager: PinnedImageManager) {
        self.pasteboard = pasteboard
        self.imageLoader = imageLoader ?? ClipboardImageLoader(pasteboard: pasteboard)
        self.pinnedImageManager = pinnedImageManager
    }

    func copy(_ screenshot: RenderedScreenshot) throws {
        let pngData = try screenshot.pngData()
        let image = NSImage(cgImage: screenshot.cgImage, size: screenshot.pointSize)
        guard let tiffData = image.tiffRepresentation else { throw ScreenshotError.imageEncodingFailed }
        let item = NSPasteboardItem()
        item.setData(pngData, forType: .png)
        item.setData(tiffData, forType: .tiff)
        pasteboard.clearContents()
        guard pasteboard.writeObjects([item]) else { throw ScreenshotError.clipboardWriteFailed }
    }

    func save(_ screenshot: RenderedScreenshot) async throws -> ScreenshotSaveResult {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = Self.defaultFileName()
        panel.allowedContentTypes = [.png]
        panel.canCreateDirectories = true
        NSApp.activate(ignoringOtherApps: true)
        let response = panel.runModal()
        guard response == .OK, let url = panel.url else { return .cancelled }
        do {
            try Self.writePNG(screenshot, to: url)
            return .saved(url)
        } catch {
            throw ScreenshotError.saveFailed
        }
    }

    /// Atomic PNG write, separated from NSSavePanel so it is unit-testable.
    static func writePNG(_ screenshot: RenderedScreenshot, to url: URL) throws {
        try screenshot.pngData().write(to: url, options: .atomic)
    }

    func pin(_ screenshot: RenderedScreenshot) throws {
        try pinnedImageManager.pin(screenshot)
    }

    func pinClipboard() throws {
        let image = try imageLoader.loadImage()
        try pinnedImageManager.pin(image)
    }

    static func defaultFileName() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        return "Pennyworth \(formatter.string(from: Date())).png"
    }
}
