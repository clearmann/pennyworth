import AppKit
import CoreGraphics

@MainActor protocol ScreenCapturing {
    func capture() async throws -> ScreenSnapshot
}

enum ScreenCapturerFactory {
    @MainActor static func make() -> ScreenCapturing {
        if #available(macOS 14.0, *) {
            return ScreenCaptureKitCapturer()
        }
        return CGScreenCapturer()
    }
}

/// Shared metadata enumeration: window info always comes from CGWindowList so both
/// capturers apply identical hit-testing filters (SCWindow exposes no alpha value).
enum ScreenWindowMetadata {
    static func currentWindows() -> [WindowDescriptor] {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                                    kCGNullWindowID) as? [[String: Any]] else {
            return []
        }
        return list.compactMap(descriptor(for:))
    }

    static func displays() -> [DisplayDescriptor] {
        NSScreen.screens.compactMap { screen in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")],
                  let id = (number as? NSNumber)?.uint32Value else { return nil }
            return DisplayDescriptor(id: id, quartzFrame: CGDisplayBounds(id), cocoaFrame: screen.frame)
        }
    }

    /// Per-display Retina scale factors for configuring capture output resolution.
    static func backingScaleFactors() -> [CGDirectDisplayID: CGFloat] {
        var result: [CGDirectDisplayID: CGFloat] = [:]
        for screen in NSScreen.screens {
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")],
                  let id = (number as? NSNumber)?.uint32Value else { continue }
            result[id] = screen.backingScaleFactor
        }
        return result
    }

    private static func descriptor(for info: [String: Any]) -> WindowDescriptor? {
        guard let number = info[kCGWindowNumber as String] as? NSNumber,
              let bounds = info[kCGWindowBounds as String] as? NSDictionary,
              let frame = CGRect(dictionaryRepresentation: bounds) else { return nil }
        let pid = (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value ?? 0
        let layer = (info[kCGWindowLayer as String] as? NSNumber)?.intValue ?? 0
        let alpha = (info[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1
        let onscreen = (info[kCGWindowIsOnscreen as String] as? NSNumber)?.boolValue ?? false
        let sharing = (info[kCGWindowSharingState as String] as? NSNumber)?.intValue ?? 1
        return WindowDescriptor(id: CGWindowID(number.uint32Value), ownerPID: pid, layer: layer,
                                quartzBounds: frame, alpha: alpha, isOnscreen: onscreen, sharingState: sharing)
    }
}

/// macOS 13 fallback. CGWindowListCreateImage is deprecated in macOS 14 and obsoleted
/// in macOS 15, so it must only run on systems without SCScreenshotManager.
final class CGScreenCapturer: ScreenCapturing {
    func capture() async throws -> ScreenSnapshot {
        let descriptors = ScreenWindowMetadata.displays()
        guard !descriptors.isEmpty else { throw ScreenshotError.captureFailed }
        var displays: [CapturedDisplay] = []
        for descriptor in descriptors {
            guard let image = CGWindowListCreateImage(descriptor.quartzFrame, .optionOnScreenOnly,
                                                      kCGNullWindowID, [.bestResolution]) else {
                throw ScreenshotError.captureFailed
            }
            displays.append(CapturedDisplay(descriptor: descriptor, image: image))
        }
        displays.sort { $0.descriptor.id < $1.descriptor.id }
        return ScreenSnapshot(displays: displays, windows: ScreenWindowMetadata.currentWindows())
    }
}
