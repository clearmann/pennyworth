import AppKit

/// Centralized visual tokens and presentation rules for Pennyworth's native AppKit surfaces.
@MainActor enum PennyworthTheme {
    // MARK: - Geometry & Radii

    static let panelCornerRadius: CGFloat = 16
    static let cardCornerRadius: CGFloat = 10
    static let iconCornerRadius: CGFloat = 8
    static let badgeCornerRadius: CGFloat = 6
    static let rowHeight: CGFloat = 56
    static let collapsedPanelHeight: CGFloat = 106

    // MARK: - Typography

    static let searchFont = NSFont.systemFont(ofSize: 21, weight: .regular)
    static let rowTitleFont = NSFont.systemFont(ofSize: 14.5, weight: .medium)
    static let rowSubtitleFont = NSFont.systemFont(ofSize: 12, weight: .regular)
    static let statusFont = NSFont.systemFont(ofSize: 11.5, weight: .regular)
    static let badgeFont = NSFont.systemFont(ofSize: 11, weight: .medium)
    static let monoBadgeFont = NSFont.monospacedSystemFont(ofSize: 11, weight: .medium)

    // MARK: - Dynamic Colors (Light / Dark)

    static let accentPrimary = dynamicColor(
        light: NSColor(calibratedRed: 0.184, green: 0.435, blue: 0.929, alpha: 1.0), // #2F6FED
        dark: NSColor(calibratedRed: 0.357, green: 0.553, blue: 0.937, alpha: 1.0)   // #5B8DEF
    )

    static let surfaceCard = dynamicColor(
        light: NSColor.white.withAlphaComponent(0.76),
        dark: NSColor(calibratedRed: 0.125, green: 0.145, blue: 0.180, alpha: 0.72)
    )

    static let surfaceElevated = dynamicColor(
        light: NSColor.black.withAlphaComponent(0.055),
        dark: NSColor.white.withAlphaComponent(0.085)
    )

    static let selectionFill = dynamicColor(
        light: NSColor(calibratedRed: 0.184, green: 0.435, blue: 0.929, alpha: 0.11),
        dark: NSColor(calibratedRed: 0.357, green: 0.553, blue: 0.937, alpha: 0.20)
    )

    static let selectionBorder = dynamicColor(
        light: NSColor(calibratedRed: 0.184, green: 0.435, blue: 0.929, alpha: 0.26),
        dark: NSColor(calibratedRed: 0.357, green: 0.553, blue: 0.937, alpha: 0.38)
    )

    static let borderHairline = dynamicColor(
        light: NSColor.black.withAlphaComponent(0.085),
        dark: NSColor.white.withAlphaComponent(0.11)
    )

    static let badgeAccentFill = dynamicColor(
        light: NSColor(calibratedRed: 0.184, green: 0.435, blue: 0.929, alpha: 0.12),
        dark: NSColor(calibratedRed: 0.357, green: 0.553, blue: 0.937, alpha: 0.22)
    )

    // MARK: - Customizable Row Action Labeling

    /// Maps a search action to the keycap hint shown on the highlighted row.
    ///
    /// Customize this mapping if you prefer icon-only ("↵") hints or verb-first labels.
    static func actionKeycapTitle(for action: SearchAction) -> String {
        switch action {
        case .openApplication, .openFile, .openURL:
            return L10n.tr("launcher.keycap.open")
        case .revealFile:
            return L10n.tr("launcher.keycap.reveal")
        case .copyText:
            return L10n.tr("launcher.keycap.copy")
        case .startScreenshot, .pinClipboardImage:
            return L10n.tr("launcher.keycap.run")
        }
    }

    private static func dynamicColor(light: NSColor, dark: NSColor) -> NSColor {
        NSColor(name: nil) { appearance in
            let match = appearance.bestMatch(from: [.darkAqua, .aqua])
            return match == .darkAqua ? dark : light
        }
    }
}
