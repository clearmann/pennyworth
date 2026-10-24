import AppKit

protocol RestorableApplication: AnyObject {
    var processIdentifier: pid_t { get }
    func restoreFocus() -> Bool
}

extension NSRunningApplication: RestorableApplication {
    func restoreFocus() -> Bool {
        if #available(macOS 14, *) { return activate(options: []) }
        return activateBeforeMacOS14()
    }

    @available(macOS, obsoleted: 14)
    private func activateBeforeMacOS14() -> Bool {
        activate(options: [.activateIgnoringOtherApps])
    }
}

@MainActor final class ApplicationFocusRestorer {
    private let frontmostApplication: () -> RestorableApplication?
    private let currentProcessIdentifier: pid_t
    private var previousApplication: RestorableApplication?

    init(frontmostApplication: @escaping () -> RestorableApplication?,
         currentProcessIdentifier: pid_t = NSRunningApplication.current.processIdentifier) {
        self.frontmostApplication = frontmostApplication
        self.currentProcessIdentifier = currentProcessIdentifier
    }

    func captureFrontmostApplication() {
        let application = frontmostApplication()
        // Re-presenting the panel must not replace the app the user came from.
        guard application?.processIdentifier != currentProcessIdentifier else { return }
        previousApplication = application
    }

    @discardableResult
    func restorePreviousApplication() -> Bool {
        let application = previousApplication
        previousApplication = nil
        return application?.restoreFocus() ?? false
    }
}
