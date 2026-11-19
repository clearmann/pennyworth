import AppKit
import ApplicationServices

/// System adapter for macOS Accessibility permission, injectable for tests.
protocol AccessibilityAccessing {
    func isTrusted() -> Bool
    func requestTrust() -> Bool
}

struct SystemAccessibilityAccess: AccessibilityAccessing {
    func isTrusted() -> Bool {
        AXIsProcessTrusted()
    }

    func requestTrust() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }
}

@MainActor protocol AccessibilitySettingsOpening {
    @discardableResult func openAccessibilitySettings() -> Bool
}

@MainActor final class SystemAccessibilitySettingsOpener: AccessibilitySettingsOpening {
    private static let settingsURL = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
    )!

    @discardableResult
    func openAccessibilitySettings() -> Bool {
        NSWorkspace.shared.open(Self.settingsURL)
    }
}
