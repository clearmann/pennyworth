import AppKit
import CoreGraphics

/// Crops the frozen display image to the selection and renders annotations into a
/// physical-pixel bitmap. Never uses NSImage.lockFocus so output resolution is explicit.
enum ScreenshotCompositor {
    static func compose(display: CapturedDisplay, selection: CGRect,
                        annotations: [Annotation] = []) throws -> RenderedScreenshot {
        let pixelRect = ScreenGeometry.pixelRect(for: selection, in: display)
        guard !pixelRect.isEmpty, !pixelRect.isNull, pixelRect.width >= 1, pixelRect.height >= 1,
              let cropped = display.image.cropping(to: pixelRect) else {
            throw ScreenshotError.captureFailed
        }
        let pointSize = pointSize(for: pixelRect, in: display)
        guard !annotations.isEmpty else {
            return RenderedScreenshot(cgImage: cropped, pointSize: pointSize)
        }
        let width = Int(pixelRect.width)
        let height = Int(pixelRect.height)
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                         isPlanar: false, colorSpaceName: .deviceRGB,
                                         bytesPerRow: 0, bitsPerPixel: 0),
              let context = NSGraphicsContext(bitmapImageRep: rep) else {
            throw ScreenshotError.imageEncodingFailed
        }
        let cgContext = context.cgContext
        cgContext.draw(cropped, in: CGRect(x: 0, y: 0, width: width, height: height))
        cgContext.saveGState()
        cgContext.scaleBy(x: display.scaleX, y: display.scaleY)
        AnnotationRenderer.draw(annotations: annotations, mosaicSource: cropped,
                                scaleX: display.scaleX, scaleY: display.scaleY, in: cgContext)
        cgContext.restoreGState()
        guard let output = rep.cgImage else { throw ScreenshotError.imageEncodingFailed }
        return RenderedScreenshot(cgImage: output, pointSize: pointSize)
    }

    static func pointSize(for pixelRect: CGRect, in display: CapturedDisplay) -> CGSize {
        CGSize(width: pixelRect.width / display.scaleX, height: pixelRect.height / display.scaleY)
    }
}
