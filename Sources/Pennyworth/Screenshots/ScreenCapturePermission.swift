import AppKit
import CoreGraphics

/// System adapter for screen-recording permission, injectable for tests.
protocol ScreenCaptureAccessing {
    func preflight() -> Bool
    func request() -> Bool
}

struct SystemScreenCaptureAccess: ScreenCaptureAccessing {
    func preflight() -> Bool { CGPreflightScreenCaptureAccess() }
    func request() -> Bool { CGRequestScreenCaptureAccess() }
}

enum ScreenCaptureGuidanceChoice {
    case openSettings
    case retry
    case cancel
}

@MainActor protocol ScreenCaptureGuidancePresenting {
    func presentGuidance() async -> ScreenCaptureGuidanceChoice
}

@MainActor protocol ScreenCaptureSettingsOpening {
    @discardableResult func openScreenCaptureSettings() -> Bool
}

@MainActor final class SystemScreenCaptureSettingsOpener: ScreenCaptureSettingsOpening {
    private static let settingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!

    @discardableResult
    func openScreenCaptureSettings() -> Bool {
        NSWorkspace.shared.open(Self.settingsURL)
    }
}

@MainActor final class AlertScreenCaptureGuidancePresenter: ScreenCaptureGuidancePresenting {
    private let runModal: @MainActor (NSAlert) -> NSApplication.ModalResponse

    init(runModal: @escaping @MainActor (NSAlert) -> NSApplication.ModalResponse = { alert in
        NSApp.activate(ignoringOtherApps: true)
        return alert.runModal()
    }) {
        self.runModal = runModal
    }

    func presentGuidance() async -> ScreenCaptureGuidanceChoice {
        let alert = NSAlert()
        alert.messageText = L10n.tr("screenshot.permission.title")
        alert.informativeText = L10n.tr("screenshot.permission.message")
        alert.alertStyle = .warning
        alert.addButton(withTitle: L10n.tr("screenshot.permission.open_settings"))
        alert.addButton(withTitle: L10n.tr("screenshot.permission.retry"))
        alert.addButton(withTitle: L10n.tr("screenshot.action.cancel"))
        switch runModal(alert) {
        case .alertFirstButtonReturn: return .openSettings
        case .alertSecondButtonReturn: return .retry
        default: return .cancel
        }
    }
}

/// Checks live permission on every attempt, requesting system access at most once per app run.
/// System requests and app guidance use separate attempts so their dialogs do not immediately overlap.
@MainActor final class ScreenCapturePermissionCoordinator {
    private let access: ScreenCaptureAccessing
    private let guidance: ScreenCaptureGuidancePresenting
    private let settingsOpener: ScreenCaptureSettingsOpening
    private var didRequestSystemAccess = false

    init(access: ScreenCaptureAccessing,
         guidance: ScreenCaptureGuidancePresenting,
         settingsOpener: ScreenCaptureSettingsOpening) {
        self.access = access
        self.guidance = guidance
        self.settingsOpener = settingsOpener
    }

    func ensureAuthorized() async throws -> Bool {
        if access.preflight() { return true }
        if !didRequestSystemAccess {
            didRequestSystemAccess = true
            // The system dialog may still be visible when the request returns false.
            return access.request() || access.preflight()
        }
        switch await guidance.presentGuidance() {
        case .openSettings:
            guard settingsOpener.openScreenCaptureSettings() else {
                throw ScreenshotError.permissionSettingsFailed
            }
            return false
        case .retry:
            return access.preflight()
        case .cancel:
            return false
        }
    }
}
