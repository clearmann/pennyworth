import CoreGraphics
import Foundation

enum SelectionHandle: String, CaseIterable, Equatable {
    case topLeft, top, topRight, right, bottomRight, bottom, bottomLeft, left
}

/// Immutable selection geometry: creation drags, moves and eight-handle resizing,
/// always clamped to one display's local bounds.
struct SelectionModel: Equatable {
    static let minimumSize = CGSize(width: 4, height: 4)
    static let dragThreshold: CGFloat = 3
    static let handleHitSlop: CGFloat = 6

    let bounds: CGRect
    let rect: CGRect?

    init(bounds: CGRect, rect: CGRect? = nil) {
        self.bounds = bounds
        self.rect = rect
    }

    static func isDrag(from start: CGPoint, to current: CGPoint) -> Bool {
        abs(current.x - start.x) >= dragThreshold || abs(current.y - start.y) >= dragThreshold
    }

    /// The rect for an in-progress creation drag, or nil while the gesture is still a click.
    func dragRect(from start: CGPoint, to current: CGPoint) -> CGRect? {
        guard Self.isDrag(from: start, to: current) else { return nil }
        let rect = ScreenGeometry.standardized(from: start, to: current)
        return ScreenGeometry.clamped(rect, to: bounds)
    }

    func moved(original: CGRect, from start: CGPoint, to current: CGPoint) -> CGRect {
        let dx = current.x - start.x
        let dy = current.y - start.y
        var x = original.minX + dx
        var y = original.minY + dy
        x = min(max(x, bounds.minX), bounds.maxX - original.width)
        y = min(max(y, bounds.minY), bounds.maxY - original.height)
        return CGRect(x: x, y: y, width: original.width, height: original.height)
    }

    func resized(handle: SelectionHandle, original: CGRect, from start: CGPoint, to current: CGPoint) -> CGRect {
        let delta = CGPoint(x: current.x - start.x, y: current.y - start.y)
        var minX = original.minX, maxX = original.maxX
        var minY = original.minY, maxY = original.maxY
        // Each handle pins the opposite edge/corner; crossing it flips the rect.
        switch handle {
        case .topLeft: minX += delta.x; maxY += delta.y
        case .top: maxY += delta.y
        case .topRight: maxX += delta.x; maxY += delta.y
        case .right: maxX += delta.x
        case .bottomRight: maxX += delta.x; minY += delta.y
        case .bottom: minY += delta.y
        case .bottomLeft: minX += delta.x; minY += delta.y
        case .left: minX += delta.x
        }
        let rect = CGRect(x: min(minX, maxX), y: min(minY, maxY),
                          width: abs(maxX - minX), height: abs(maxY - minY))
        return ScreenGeometry.clamped(rect, to: bounds)
    }

    func handle(at point: CGPoint) -> SelectionHandle? {
        guard let rect else { return nil }
        for handle in SelectionHandle.allCases {
            if Self.handleRect(for: handle, in: rect).insetBy(dx: -Self.handleHitSlop, dy: -Self.handleHitSlop).contains(point) {
                return handle
            }
        }
        return nil
    }

    func contains(_ point: CGPoint) -> Bool {
        rect?.contains(point) ?? false
    }

    static func handleRect(for handle: SelectionHandle, in rect: CGRect) -> CGRect {
        let size = CGSize(width: 6, height: 6)
        let center: CGPoint
        switch handle {
        case .topLeft: center = CGPoint(x: rect.minX, y: rect.maxY)
        case .top: center = CGPoint(x: rect.midX, y: rect.maxY)
        case .topRight: center = CGPoint(x: rect.maxX, y: rect.maxY)
        case .right: center = CGPoint(x: rect.maxX, y: rect.midY)
        case .bottomRight: center = CGPoint(x: rect.maxX, y: rect.minY)
        case .bottom: center = CGPoint(x: rect.midX, y: rect.minY)
        case .bottomLeft: center = CGPoint(x: rect.minX, y: rect.minY)
        case .left: center = CGPoint(x: rect.minX, y: rect.midY)
        }
        return CGRect(x: center.x - size.width / 2, y: center.y - size.height / 2,
                      width: size.width, height: size.height)
    }
}
