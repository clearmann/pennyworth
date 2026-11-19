import Foundation

enum ScrollSmoothness: String, Codable, Equatable, CaseIterable {
    case crisp
    case balanced
    case silky

    var timeConstant: TimeInterval {
        switch self {
        case .crisp: return 0.045
        case .balanced: return 0.075
        case .silky: return 0.115
        }
    }

    var title: String {
        L10n.tr("mouse.smoothness.\(rawValue)")
    }
}

struct MouseScrollSettings: Codable, Equatable {
    static let speedRange: ClosedRange<Double> = 0.5...3.0
    static let defaultSpeed: Double = 1.0
    static let defaults = MouseScrollSettings()

    let reverseScrollDirection: Bool
    let smoothScrolling: Bool
    let scrollSpeed: Double
    let smoothness: ScrollSmoothness

    init(
        reverseScrollDirection: Bool = false,
        smoothScrolling: Bool = false,
        scrollSpeed: Double = defaultSpeed,
        smoothness: ScrollSmoothness = .balanced
    ) {
        self.reverseScrollDirection = reverseScrollDirection
        self.smoothScrolling = smoothScrolling
        self.scrollSpeed = scrollSpeed
        self.smoothness = smoothness
    }

    var isActive: Bool {
        reverseScrollDirection || smoothScrolling || abs(scrollSpeed - Self.defaultSpeed) > 0.001
    }

    static func validate(_ value: MouseScrollSettings) throws {
        guard value.scrollSpeed.isFinite, speedRange.contains(value.scrollSpeed) else {
            throw MouseScrollSettingsError.invalidScrollSpeed
        }
    }
}

enum MouseScrollSettingsError: LocalizedError {
    case invalidScrollSpeed

    var errorDescription: String? {
        switch self {
        case .invalidScrollSpeed:
            return L10n.tr("mouse.error.invalid_speed")
        }
    }
}
