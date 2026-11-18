import AppKit
import CoreGraphics

/// Shared annotation drawing for the live preview and the final composed PNG.
/// The caller supplies a CGContext already transformed to selection-local AppKit
/// points (bottom-left origin); mosaicSource is the cropped selection image in pixels.
enum AnnotationRenderer {
    static func draw(annotations: [Annotation], draft: Annotation? = nil,
                     mosaicSource: CGImage?, scaleX: CGFloat, scaleY: CGFloat,
                     in context: CGContext) {
        for annotation in annotations {
            draw(annotation, mosaicSource: mosaicSource, scaleX: scaleX, scaleY: scaleY, in: context)
        }
        if let draft {
            draw(draft, mosaicSource: mosaicSource, scaleX: scaleX, scaleY: scaleY, in: context)
        }
    }

    private static func draw(_ annotation: Annotation, mosaicSource: CGImage?,
                             scaleX: CGFloat, scaleY: CGFloat, in context: CGContext) {
        let color = annotation.style.color.cgColor
        switch annotation.geometry {
        case .rectangle(let rect):
            stroke(path: { $0.addRect(rect) }, color: color, width: annotation.style.lineWidth, in: context)
        case .ellipse(let rect):
            stroke(path: { $0.addEllipse(in: rect) }, color: color, width: annotation.style.lineWidth, in: context)
        case .arrow(let arrow):
            drawArrow(arrow, style: annotation.style, in: context)
        case .pen(let points):
            guard points.count > 1 else { return }
            stroke(path: { path in
                path.move(to: points[0])
                for point in points.dropFirst() { path.addLine(to: point) }
            }, color: color, width: annotation.style.lineWidth, in: context)
        case .text(let text):
            drawText(text, style: annotation.style, in: context)
        case .mosaic(let rect):
            drawMosaic(rect, style: annotation.style, source: mosaicSource,
                       scaleX: scaleX, scaleY: scaleY, in: context)
        }
    }

    private static func stroke(path build: (CGMutablePath) -> Void, color: CGColor,
                               width: CGFloat, in context: CGContext) {
        let path = CGMutablePath()
        build(path)
        context.saveGState()
        context.setStrokeColor(color)
        context.setLineWidth(width)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.addPath(path)
        context.strokePath()
        context.restoreGState()
    }

    private static func drawArrow(_ arrow: ArrowGeometry, style: AnnotationStyle, in context: CGContext) {
        let dx = arrow.end.x - arrow.start.x
        let dy = arrow.end.y - arrow.start.y
        let length = hypot(dx, dy)
        guard length > 0.5 else { return }
        let angle = atan2(dy, dx)
        let headLength = min(max(12, style.lineWidth * 4), length)
        let wingAngle = CGFloat.pi / 6
        let wing1 = CGPoint(x: arrow.end.x - headLength * cos(angle - wingAngle),
                            y: arrow.end.y - headLength * sin(angle - wingAngle))
        let wing2 = CGPoint(x: arrow.end.x - headLength * cos(angle + wingAngle),
                            y: arrow.end.y - headLength * sin(angle + wingAngle))
        stroke(path: { path in
            path.move(to: arrow.start)
            path.addLine(to: arrow.end)
        }, color: style.color.cgColor, width: style.lineWidth, in: context)
        context.saveGState()
        context.setFillColor(style.color.cgColor)
        let head = CGMutablePath()
        head.move(to: arrow.end)
        head.addLine(to: wing1)
        head.addLine(to: wing2)
        head.closeSubpath()
        context.addPath(head)
        context.fillPath()
        context.restoreGState()
    }

    private static func drawText(_ text: TextGeometry, style: AnnotationStyle, in context: CGContext) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: style.fontSize, weight: .medium),
            .foregroundColor: style.color.nsColor,
        ]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text.text, attributes: attributes))
        var ascent: CGFloat = 0
        var descent: CGFloat = 0
        var leading: CGFloat = 0
        _ = CTLineGetTypographicBounds(line, &ascent, &descent, &leading)
        // Vertically center the single line inside its frame (bottom-left coordinates).
        let baselineY = text.frame.minY + (text.frame.height - ascent - descent) / 2 + descent
        context.saveGState()
        context.textMatrix = .identity
        context.textPosition = CGPoint(x: text.frame.minX, y: baselineY)
        CTLineDraw(line, context)
        context.restoreGState()
    }

    /// True pixelation: downsample the source region, then upscale with no interpolation.
    private static func drawMosaic(_ rect: CGRect, style: AnnotationStyle, source: CGImage?,
                                   scaleX: CGFloat, scaleY: CGFloat, in context: CGContext) {
        guard let source, rect.width > 0, rect.height > 0 else { return }
        let selectionHeight = CGFloat(source.height) / scaleY
        let pixelRect = CGRect(x: rect.minX * scaleX,
                               y: (selectionHeight - rect.maxY) * scaleY,
                               width: rect.width * scaleX,
                               height: rect.height * scaleY).integral
        guard let subImage = source.cropping(to: pixelRect) else { return }
        let blockSize = max(1, style.mosaicBlockSize)
        let lowWidth = max(1, Int((pixelRect.width / CGFloat(blockSize)).rounded()))
        let lowHeight = max(1, Int((pixelRect.height / CGFloat(blockSize)).rounded()))
        guard let lowContext = CGContext(data: nil, width: lowWidth, height: lowHeight,
                                         bitsPerComponent: 8, bytesPerRow: lowWidth * 4,
                                         space: CGColorSpaceCreateDeviceRGB(),
                                         bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
        lowContext.draw(subImage, in: CGRect(x: 0, y: 0, width: lowWidth, height: lowHeight))
        guard let lowImage = lowContext.makeImage() else { return }
        context.saveGState()
        context.clip(to: rect)
        context.interpolationQuality = .none
        context.draw(lowImage, in: rect)
        context.restoreGState()
    }
}

extension RGBAColor {
    var cgColor: CGColor { CGColor(red: red, green: green, blue: blue, alpha: alpha) }
    var nsColor: NSColor { NSColor(red: red, green: green, blue: blue, alpha: alpha) }
}
