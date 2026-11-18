import Foundation

/// Launcher command results for screenshot capture and clipboard pinning.
enum ScreenshotProvider {
    static func result(for command: ScreenshotCommand) -> SearchResult {
        switch command {
        case .capture:
            return SearchResult(id: "screenshot.capture",
                                title: L10n.tr("launcher.screenshot.capture"),
                                subtitle: L10n.tr("launcher.screenshot.capture_subtitle"),
                                symbol: "camera.viewfinder",
                                action: .startScreenshot)
        case .pinClipboard:
            return SearchResult(id: "screenshot.pin_clipboard",
                                title: L10n.tr("launcher.screenshot.pin_clipboard"),
                                subtitle: L10n.tr("launcher.screenshot.pin_clipboard_subtitle"),
                                symbol: "pin.square",
                                action: .pinClipboardImage)
        }
    }
}
