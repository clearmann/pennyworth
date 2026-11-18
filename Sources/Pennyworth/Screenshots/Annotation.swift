import CoreGraphics
import Foundation

enum AnnotationTool: String, CaseIterable, Equatable {
    case selection, rectangle, ellipse, arrow, pen, text, mosaic
}

struct RGBAColor: Equatable {
    let red: Double
    let green: Double
    let blue: Double
    let alpha: Double

    static let red = RGBAColor(red: 1, green: 0, blue: 0, alpha: 1)
    static let orange = RGBAColor(red: 1, green: 0.5, blue: 0, alpha: 1)
    static let yellow = RGBAColor(red: 1, green: 1, blue: 0, alpha: 1)
    static let green = RGBAColor(red: 0, green: 1, blue: 0, alpha: 1)
    static let blue = RGBAColor(red: 0, green: 0, blue: 1, alpha: 1)
    static let white = RGBAColor(red: 1, green: 1, blue: 1, alpha: 1)
    static let black = RGBAColor(red: 0, green: 0, blue: 0, alpha: 1)
}

struct AnnotationStyle: Equatable {
    let color: RGBAColor
    let lineWidth: CGFloat
    let fontSize: CGFloat
    let mosaicBlockSize: Int

    static let `default` = AnnotationStyle(
        color: .red,
        lineWidth: 3,
        fontSize: 16,
        mosaicBlockSize: 12
    )
}

struct ArrowGeometry: Equatable {
    let start: CGPoint
    let end: CGPoint
}

struct TextGeometry: Equatable {
    let frame: CGRect
    let text: String
}

enum AnnotationGeometry: Equatable {
    case rectangle(CGRect)
    case ellipse(CGRect)
    case arrow(ArrowGeometry)
    case pen([CGPoint])
    case text(TextGeometry)
    case mosaic(CGRect)
}

struct Annotation: Identifiable, Equatable {
    let id: UUID
    let geometry: AnnotationGeometry
    let style: AnnotationStyle

    init(id: UUID = UUID(), geometry: AnnotationGeometry, style: AnnotationStyle) {
        self.id = id
        self.geometry = geometry
        self.style = style
    }

    func withGeometry(_ geometry: AnnotationGeometry) -> Annotation {
        Annotation(id: id, geometry: geometry, style: style)
    }

    func withText(_ text: String) -> Annotation {
        guard case .text(let geometry) = geometry else { return self }
        let updated = TextGeometry(frame: geometry.frame, text: text)
        return withGeometry(.text(updated))
    }
}
