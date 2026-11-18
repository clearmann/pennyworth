import AppKit
import CoreGraphics
import ScreenCaptureKit

/// Primary capturer on macOS 14+. Output dimensions are points × backingScaleFactor:
/// CGDisplayPixelsWide reports the scaled "UI looks like" size, not physical pixels.
@available(macOS 14.0, *)
final class ScreenCaptureKitCapturer: ScreenCapturing {
    func capture() async throws -> ScreenSnapshot {
        // SCShareableContent.current is the async form of getShareableContentWithCompletionHandler;
        // desktop filtering happens in WindowHitTester, and the frozen image must include the wallpaper.
        let content = try await SCShareableContent.current
        let descriptorsByID = Dictionary(uniqueKeysWithValues: ScreenWindowMetadata.displays().map { ($0.id, $0) })
        let scaleByID = ScreenWindowMetadata.backingScaleFactors()
        var displays: [CapturedDisplay] = []
        for scDisplay in content.displays {
            guard let descriptor = descriptorsByID[scDisplay.displayID] else { continue }
            let configuration = SCStreamConfiguration()
            // CGDisplayPixelsWide reports the scaled "UI looks like" size (e.g. 1920 on a 4K
            // panel), NOT physical pixels. backingScaleFactor is what restores Retina resolution.
            let scale = scaleByID[scDisplay.displayID] ?? 1
            configuration.width = Int(descriptor.quartzFrame.width * scale)
            configuration.height = Int(descriptor.quartzFrame.height * scale)
            configuration.showsCursor = false
            let filter = SCContentFilter(display: scDisplay, excludingWindows: [])
            do {
                let image = try await SCScreenshotManager.captureImage(contentFilter: filter,
                                                                       configuration: configuration)
                displays.append(CapturedDisplay(descriptor: descriptor, image: image))
            } catch {
                throw ScreenshotError.captureFailed
            }
        }
        guard !displays.isEmpty else { throw ScreenshotError.captureFailed }
        displays.sort { $0.descriptor.id < $1.descriptor.id }
        return ScreenSnapshot(displays: displays, windows: ScreenWindowMetadata.currentWindows())
    }
}
