import CoreGraphics
import Foundation

/// Pure coordinate math for the screenshot feature.
///
/// Quartz global coordinates have a top-left origin; AppKit uses bottom-left.
/// Selections are stored per display in local AppKit points; pixel rects use
/// the CGImage's own top-left origin so they can feed `CGImage.cropping(to:)` directly.
enum ScreenGeometry {
    static func quartzToCocoa(_ rect: CGRect, mainDisplayHeight: CGFloat) -> CGRect {
        CGRect(x: rect.minX, y: mainDisplayHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    static func localRect(forCocoaGlobal rect: CGRect, in display: DisplayDescriptor) -> CGRect {
        rect.offsetBy(dx: -display.cocoaFrame.minX, dy: -display.cocoaFrame.minY)
    }

    static func localRect(forQuartzGlobal rect: CGRect, in display: DisplayDescriptor,
                          mainDisplayHeight: CGFloat) -> CGRect {
        localRect(forCocoaGlobal: quartzToCocoa(rect, mainDisplayHeight: mainDisplayHeight), in: display)
    }

    static func standardized(from start: CGPoint, to end: CGPoint) -> CGRect {
        CGRect(x: min(start.x, end.x), y: min(start.y, end.y),
               width: abs(end.x - start.x), height: abs(end.y - start.y))
    }

    static func clamped(_ rect: CGRect, to bounds: CGRect) -> CGRect {
        rect.intersection(bounds)
    }

    /// Converts a local AppKit-point selection into physical-pixel image coordinates (top-left origin).
    static func pixelRect(for localRect: CGRect, in display: CapturedDisplay) -> CGRect {
        let height = display.descriptor.quartzFrame.height
        let x = (localRect.minX * display.scaleX).rounded()
        let y = ((height - localRect.maxY) * display.scaleY).rounded()
        let width = (localRect.width * display.scaleX).rounded()
        let pixelHeight = (localRect.height * display.scaleY).rounded()
        let rect = CGRect(x: x, y: y, width: width, height: pixelHeight)
        return rect.intersection(CGRect(x: 0, y: 0, width: display.image.width, height: display.image.height))
    }
}
