import AppKit

/// Visual design tokens shared across the redesigned Pennyworth Settings window.
/// Aligned with `PennyworthTheme` for consistent Light and Dark macOS appearance.
@MainActor enum SettingsStyle {
    enum StatusLevel {
        case info
        case success
        case warning
        case error
    }

    // MARK: - Geometry

    static let windowDefaultSize = NSSize(width: 920, height: 650)
    static let windowMinSize = NSSize(width: 780, height: 580)
    static let sidebarWidth: CGFloat = 208
    static let sidebarTopInset: CGFloat = 46
    static let contentHorizontalPadding: CGFloat = 28
    static let contentTopPadding: CGFloat = 34
    static let contentBottomPadding: CGFloat = 28
    static let cardCornerRadius: CGFloat = 10
    static let controlCornerRadius: CGFloat = 7
    static let rowHorizontalPadding: CGFloat = 14
    static let rowVerticalPadding: CGFloat = 11
    static let sectionSpacing: CGFloat = 20

    // MARK: - Typography

    static let pageTitleFont = NSFont.systemFont(ofSize: 22, weight: .semibold)
    static let pageSubtitleFont = NSFont.systemFont(ofSize: 12.5, weight: .regular)
    static let sidebarGroupFont = NSFont.systemFont(ofSize: 11, weight: .semibold)
    static let sidebarItemFont = NSFont.systemFont(ofSize: 13, weight: .regular)
    static let sidebarItemSelectedFont = NSFont.systemFont(ofSize: 13, weight: .medium)
    static let sectionTitleFont = NSFont.systemFont(ofSize: 12.5, weight: .semibold)
    static let rowTitleFont = NSFont.systemFont(ofSize: 13, weight: .medium)
    static let rowSubtitleFont = NSFont.systemFont(ofSize: 11.5, weight: .regular)
    static let footnoteFont = NSFont.systemFont(ofSize: 11.5, weight: .regular)
    static let badgeFont = NSFont.systemFont(ofSize: 11, weight: .medium)
    static let keycapFont = NSFont.systemFont(ofSize: 12.5, weight: .medium)
    static let monoKeycapFont = NSFont.monospacedSystemFont(ofSize: 11.5, weight: .medium)

    // MARK: - Dynamic Colors

    static let canvasBackground = dynamicColor(
        light: NSColor(calibratedRed: 0.961, green: 0.961, blue: 0.969, alpha: 1.0), // #F5F5F7
        dark: NSColor(calibratedRed: 0.110, green: 0.114, blue: 0.125, alpha: 1.0)   // #1C1D20
    )

    static let cardBackground = dynamicColor(
        light: NSColor.white,
        dark: NSColor(calibratedRed: 0.145, green: 0.153, blue: 0.169, alpha: 1.0)   // #25272B
    )

    static let cardBorder = dynamicColor(
        light: NSColor.black.withAlphaComponent(0.08),
        dark: NSColor.white.withAlphaComponent(0.095)
    )

    static let dividerHairline = dynamicColor(
        light: NSColor.black.withAlphaComponent(0.065),
        dark: NSColor.white.withAlphaComponent(0.075)
    )

    static let paneDivider = dynamicColor(
        light: NSColor(calibratedRed: 0.886, green: 0.890, blue: 0.902, alpha: 1.0),
        dark: NSColor(calibratedRed: 0.192, green: 0.200, blue: 0.220, alpha: 1.0)
    )

    static let secondaryText = dynamicColor(
        light: NSColor(calibratedRed: 0.415, green: 0.427, blue: 0.455, alpha: 1.0),
        dark: NSColor(calibratedRed: 0.620, green: 0.639, blue: 0.678, alpha: 1.0)
    )

    static let sidebarGroupText = dynamicColor(
        light: NSColor(calibratedRed: 0.460, green: 0.475, blue: 0.505, alpha: 1.0),
        dark: NSColor(calibratedRed: 0.545, green: 0.565, blue: 0.605, alpha: 1.0)
    )

    static let rowHoverFill = dynamicColor(
        light: NSColor.black.withAlphaComponent(0.032),
        dark: NSColor.white.withAlphaComponent(0.048)
    )

    static let sidebarHoverFill = dynamicColor(
        light: NSColor.black.withAlphaComponent(0.048),
        dark: NSColor.white.withAlphaComponent(0.065)
    )

    static let sidebarSelectedFill = PennyworthTheme.selectionFill
    static let sidebarSelectedBorder = PennyworthTheme.selectionBorder

    static let keycapFill = dynamicColor(
        light: NSColor(calibratedRed: 0.953, green: 0.957, blue: 0.965, alpha: 1.0),
        dark: NSColor.white.withAlphaComponent(0.075)
    )

    static let keycapEmptyFill = dynamicColor(
        light: NSColor.black.withAlphaComponent(0.025),
        dark: NSColor.white.withAlphaComponent(0.04)
    )

    static let keycapBorder = dynamicColor(
        light: NSColor.black.withAlphaComponent(0.115),
        dark: NSColor.white.withAlphaComponent(0.13)
    )

    static let keycapHoverBorder = dynamicColor(
        light: NSColor.black.withAlphaComponent(0.24),
        dark: NSColor.white.withAlphaComponent(0.26)
    )

    static let keycapRecordingFill = PennyworthTheme.selectionFill

    static let badgeNeutralFill = dynamicColor(
        light: NSColor.black.withAlphaComponent(0.055),
        dark: NSColor.white.withAlphaComponent(0.085)
    )

    static let destructiveHoverFill = dynamicColor(
        light: NSColor.systemRed.withAlphaComponent(0.10),
        dark: NSColor.systemRed.withAlphaComponent(0.18)
    )

    static func statusBackground(for level: StatusLevel) -> NSColor {
        switch level {
        case .info:
            return PennyworthTheme.badgeAccentFill
        case .success:
            return dynamicColor(
                light: NSColor.systemGreen.withAlphaComponent(0.11),
                dark: NSColor.systemGreen.withAlphaComponent(0.18)
            )
        case .warning:
            return dynamicColor(
                light: NSColor.systemOrange.withAlphaComponent(0.12),
                dark: NSColor.systemOrange.withAlphaComponent(0.19)
            )
        case .error:
            return dynamicColor(
                light: NSColor.systemRed.withAlphaComponent(0.11),
                dark: NSColor.systemRed.withAlphaComponent(0.19)
            )
        }
    }

    static func statusBorder(for level: StatusLevel) -> NSColor {
        switch level {
        case .info:
            return PennyworthTheme.selectionBorder
        case .success:
            return NSColor.systemGreen.withAlphaComponent(0.28)
        case .warning:
            return NSColor.systemOrange.withAlphaComponent(0.32)
        case .error:
            return NSColor.systemRed.withAlphaComponent(0.30)
        }
    }

    static func statusForeground(for level: StatusLevel) -> NSColor {
        switch level {
        case .info: return PennyworthTheme.accentPrimary
        case .success: return .systemGreen
        case .warning: return .systemOrange
        case .error: return .systemRed
        }
    }

    static func statusSymbolName(for level: StatusLevel) -> String {
        switch level {
        case .info: return "info.circle.fill"
        case .success: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .error: return "xmark.octagon.fill"
        }
    }

    static func abbreviatedPath(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if path == home { return "~" }
        if path.hasPrefix(home + "/") {
            return "~" + String(path.dropFirst(home.count))
        }
        return path
    }

    static func applicationIcon(forPath path: String) -> NSImage {
        if !path.isEmpty, FileManager.default.fileExists(atPath: path) {
            return NSWorkspace.shared.icon(forFile: path)
        }
        return NSImage(systemSymbolName: "app.fill", accessibilityDescription: nil)
            ?? NSImage(size: NSSize(width: 28, height: 28))
    }

    static func folderIcon(forPath path: String) -> NSImage {
        if !path.isEmpty, FileManager.default.fileExists(atPath: path) {
            return NSWorkspace.shared.icon(forFile: path)
        }
        let image = NSImage(systemSymbolName: "folder.fill", accessibilityDescription: nil)
            ?? NSImage(size: NSSize(width: 24, height: 24))
        return image
    }

    static func makeButton(
        title: String,
        symbolName: String? = nil,
        primary: Bool = false,
        target: AnyObject?,
        action: Selector?
    ) -> NSButton {
        let button = NSButton(title: title, target: target, action: action)
        button.bezelStyle = .rounded
        button.controlSize = .regular
        button.font = .systemFont(ofSize: 12.5, weight: primary ? .medium : .regular)
        if let symbolName,
           let icon = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil) {
            let config = NSImage.SymbolConfiguration(pointSize: 12, weight: .medium)
            button.image = icon.withSymbolConfiguration(config)
            button.imagePosition = .imageLeading
        }
        if primary {
            button.bezelColor = PennyworthTheme.accentPrimary
        }
        return button
    }

    private static func dynamicColor(light: NSColor, dark: NSColor) -> NSColor {
        NSColor(name: nil) { appearance in
            let match = appearance.bestMatch(from: [.darkAqua, .aqua])
            return match == .darkAqua ? dark : light
        }
    }
}
