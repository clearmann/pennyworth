import AppKit
import CoreGraphics

/// A physical display in both Quartz (top-left origin) and AppKit (bottom-left origin) coordinates.
struct DisplayDescriptor: Equatable {
    let id: CGDirectDisplayID
    let quartzFrame: CGRect
    let cocoaFrame: CGRect
}

/// One display's frozen full-screen image and the scale factors between points and physical pixels.
struct CapturedDisplay {
    let descriptor: DisplayDescriptor
    let image: CGImage

    var scaleX: CGFloat { CGFloat(image.width) / descriptor.quartzFrame.width }
    var scaleY: CGFloat { CGFloat(image.height) / descriptor.quartzFrame.height }
    var localBounds: CGRect { CGRect(origin: .zero, size: descriptor.quartzFrame.size) }
}

/// Metadata for a single on-screen window, captured in CGWindowList front-to-back order.
struct WindowDescriptor: Equatable {
    let id: CGWindowID
    let ownerPID: pid_t
    let layer: Int
    let quartzBounds: CGRect
    let alpha: Double
    let isOnscreen: Bool
    let sharingState: Int
}

/// The immutable input to a screenshot session: frozen displays plus window metadata.
struct ScreenSnapshot {
    let displays: [CapturedDisplay]
    let windows: [WindowDescriptor]
}

/// The final cropped and annotated image. Keeps physical pixels and point size separate
/// so Retina output never doubles the pinned window size.
struct RenderedScreenshot {
    let cgImage: CGImage
    let pointSize: CGSize

    var pixelSize: CGSize { CGSize(width: cgImage.width, height: cgImage.height) }

    func pngData() throws -> Data {
        let rep = NSBitmapImageRep(cgImage: cgImage)
        guard let data = rep.representation(using: .png, properties: [:]) else {
            throw ScreenshotError.imageEncodingFailed
        }
        return data
    }
}

enum ScreenshotPhase: Equatable {
    case idle
    case requestingPermission
    case capturing
    case selecting
    case annotating
    case saving
    case finishing
}

enum ScreenshotError: LocalizedError, Equatable {
    case captureFailed
    case permissionSettingsFailed
    case imageEncodingFailed
    case clipboardImageMissing
    case clipboardWriteFailed
    case saveFailed
    case pinLimitExceeded
    case sessionAlreadyActive

    var errorDescription: String? {
        switch self {
        case .captureFailed: return L10n.tr("screenshot.error.capture_failed")
        case .permissionSettingsFailed: return L10n.tr("screenshot.permission.settings_failed")
        case .imageEncodingFailed: return L10n.tr("screenshot.error.image_encoding")
        case .clipboardImageMissing: return L10n.tr("screenshot.error.clipboard_image_missing")
        case .clipboardWriteFailed: return L10n.tr("screenshot.error.clipboard_write")
        case .saveFailed: return L10n.tr("screenshot.error.save_failed")
        case .pinLimitExceeded: return L10n.tr("screenshot.error.pin_limit")
        case .sessionAlreadyActive: return L10n.tr("screenshot.error.session_active")
        }
    }
}

/// The two entry points the launcher and status bar menu can invoke.
/// `startScreenshot()` returning means the session was accepted, not that capture finished.
@MainActor protocol ScreenshotActionHandling {
    func startScreenshot() throws
    func pinClipboardImage() throws
}
