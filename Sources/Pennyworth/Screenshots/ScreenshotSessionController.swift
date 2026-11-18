import AppKit

/// The single screenshot session state machine.
/// A session UUID invalidates late async capture results after a cancel.
@MainActor final class ScreenshotSessionController: NSObject, ScreenshotActionHandling, ScreenshotOverlayViewDelegate {
    private let capturer: ScreenCapturing
    private let permission: ScreenCapturePermissionCoordinator
    private let overlay: ScreenshotOverlayPresenting
    private let output: ScreenshotOutputHandling

    private(set) var phase: ScreenshotPhase = .idle
    private var sessionID = UUID()
    private var snapshot: ScreenSnapshot?

    /// Hide launcher panels before capturing. Must not touch pinned image windows.
    var onWillCapture: (() -> Void)?
    /// Restore previous application focus after Esc-cancel.
    var onCancelRestoreFocus: (() -> Void)?
    var onError: ((Error) -> Void)?

    init(capturer: ScreenCapturing,
         permission: ScreenCapturePermissionCoordinator,
         overlay: ScreenshotOverlayPresenting,
         output: ScreenshotOutputHandling) {
        self.capturer = capturer
        self.permission = permission
        self.overlay = overlay
        self.output = output
        super.init()
    }

    // MARK: - ScreenshotActionHandling

    func startScreenshot() throws {
        guard phase == .idle else { return } // Repeated hotkey presses never interrupt an active session.
        phase = .requestingPermission
        sessionID = UUID()
        let id = sessionID
        onWillCapture?()
        Task { [weak self] in
            await self?.beginCapture(session: id)
        }
    }

    func pinClipboardImage() throws {
        try output.pinClipboard()
    }

    func cancel() {
        guard phase != .idle else { return }
        finish(restoreFocus: true)
    }

    // MARK: - Capture pipeline

    private func beginCapture(session id: UUID) async {
        do {
            let authorized = try await permission.ensureAuthorized()
            guard isCurrent(id) else { return }
            guard authorized else {
                // Leave focus with the system permission dialog or Settings, not the previous app.
                finish(restoreFocus: false)
                return
            }
            phase = .capturing
            let captured = try await capturer.capture()
            guard isCurrent(id) else { return }
            snapshot = captured
            phase = .selecting
            overlay.present(snapshot: captured, delegate: self)
        } catch {
            report(error)
        }
    }

    private func isCurrent(_ id: UUID) -> Bool {
        id == sessionID && phase != .idle
    }

    private func finish(restoreFocus: Bool) {
        phase = .idle
        sessionID = UUID()
        snapshot = nil
        overlay.dismiss()
        if restoreFocus { onCancelRestoreFocus?() }
    }

    private func report(_ error: Error) {
        // Failures keep any active selection/annotations alive; only pre-overlay failures end the session.
        if snapshot == nil {
            finish(restoreFocus: false)
        } else {
            phase = overlay.currentSelection == nil ? .selecting : .annotating
        }
        onError?(error)
    }

    // MARK: - ScreenshotOverlayViewDelegate

    func overlayViewDidBecomeActive(_ view: ScreenshotOverlayView) {}

    func overlayView(_ view: ScreenshotOverlayView, didChangeSelection rect: CGRect?) {
        guard phase == .selecting || phase == .annotating else { return }
        phase = rect == nil ? .selecting : .annotating
    }

    func overlayViewDidCancel(_ view: ScreenshotOverlayView) {
        cancel()
    }

    func overlayViewDidConfirm(_ view: ScreenshotOverlayView) {
        confirmSelection()
    }

    func overlayViewDidRequestSave(_ view: ScreenshotOverlayView) {
        saveSelection()
    }

    func overlayViewDidRequestPin(_ view: ScreenshotOverlayView) {
        pinSelection()
    }

    private func composeSelection() throws -> RenderedScreenshot {
        guard let selection = overlay.currentSelection else { throw ScreenshotError.captureFailed }
        return try ScreenshotCompositor.compose(display: selection.display, selection: selection.rect,
                                                annotations: selection.annotations)
    }

    func confirmSelection() {
        guard phase == .selecting || phase == .annotating,
              overlay.currentSelection != nil else { return }
        phase = .finishing
        do {
            try output.copy(composeSelection())
            finish(restoreFocus: false)
        } catch {
            report(error)
        }
    }

    func saveSelection() {
        guard phase == .selecting || phase == .annotating,
              overlay.currentSelection != nil else { return }
        phase = .saving
        // The .screenSaver overlay would cover NSSavePanel; hide it until the panel closes.
        overlay.setOverlaysHidden(true)
        Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await self.output.save(self.composeSelection())
                switch result {
                case .saved:
                    self.finish(restoreFocus: false)
                case .cancelled:
                    self.overlay.setOverlaysHidden(false)
                    self.phase = .annotating
                }
            } catch {
                self.overlay.setOverlaysHidden(false)
                self.report(error)
            }
        }
    }

    func pinSelection() {
        guard phase == .selecting || phase == .annotating,
              overlay.currentSelection != nil else { return }
        phase = .finishing
        do {
            try output.pin(composeSelection())
            // The overlay closes; the pinned image lives on independently.
            finish(restoreFocus: false)
        } catch {
            report(error)
        }
    }
}
