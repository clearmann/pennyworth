import AppKit

@MainActor protocol ScreenshotOverlayPresenting: AnyObject {
    func present(snapshot: ScreenSnapshot, delegate: ScreenshotOverlayViewDelegate)
    func dismiss()
    /// Hide overlays while a modal save panel is up (they sit at .screenSaver level).
    func setOverlaysHidden(_ hidden: Bool)
    var currentSelection: (display: CapturedDisplay, rect: CGRect, annotations: [Annotation])? { get }
}

/// Owns one overlay panel per display and routes the active display's events to the session.
@MainActor final class ScreenshotOverlayController: NSObject, ScreenshotOverlayPresenting, ScreenshotOverlayViewDelegate {
    private var panels: [ScreenshotOverlayPanel] = []
    var activeView: ScreenshotOverlayView?
    private weak var sessionDelegate: ScreenshotOverlayViewDelegate?

    var currentSelection: (display: CapturedDisplay, rect: CGRect, annotations: [Annotation])? {
        guard let view = activeView, let rect = view.selection.rect else { return nil }
        return (display: view.display, rect: rect, annotations: view.editor.history.current)
    }

    func setOverlaysHidden(_ hidden: Bool) {
        for panel in panels {
            if hidden { panel.orderOut(nil) } else { panel.orderFront(nil) }
        }
    }

    func present(snapshot: ScreenSnapshot, delegate: ScreenshotOverlayViewDelegate) {
        dismiss()
        sessionDelegate = delegate
        let mainDisplayHeight = NSScreen.screens.first?.frame.height ?? CGDisplayBounds(CGMainDisplayID()).height
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let mouseLocation = NSEvent.mouseLocation
        for display in snapshot.displays {
            let panel = ScreenshotOverlayPanel(contentRect: display.descriptor.cocoaFrame,
                                               styleMask: [], backing: .buffered, defer: false)
            let view = ScreenshotOverlayView(frame: NSRect(origin: .zero, size: display.descriptor.cocoaFrame.size),
                                             display: display, windows: snapshot.windows,
                                             mainDisplayHeight: mainDisplayHeight, ownPID: ownPID)
            view.delegate = self
            panel.contentView = view
            panel.orderFront(nil)
            panels.append(panel)
            if NSMouseInRect(mouseLocation, display.descriptor.cocoaFrame, false) {
                activeView = view
                panel.makeKeyAndOrderFront(nil)
                panel.makeFirstResponder(view)
            }
        }
        // Fallback when the mouse is somehow outside every display.
        if activeView == nil, let panel = panels.first {
            activeView = panel.contentView as? ScreenshotOverlayView
            panel.makeKeyAndOrderFront(nil)
            panel.makeFirstResponder(panel.contentView)
        }
    }

    func dismiss() {
        for panel in panels {
            panel.contentView = nil
            panel.orderOut(nil)
        }
        panels = []
        activeView = nil
        sessionDelegate = nil
    }

    // MARK: - ScreenshotOverlayViewDelegate

    func overlayViewDidBecomeActive(_ view: ScreenshotOverlayView) {
        guard activeView !== view else { return }
        activeView = view
        view.window?.makeKeyAndOrderFront(nil)
        view.window?.makeFirstResponder(view)
        sessionDelegate?.overlayView(view, didChangeSelection: view.selection.rect)
    }

    func overlayView(_ view: ScreenshotOverlayView, didChangeSelection rect: CGRect?) {
        sessionDelegate?.overlayView(view, didChangeSelection: rect)
    }

    func overlayViewDidCancel(_ view: ScreenshotOverlayView) {
        sessionDelegate?.overlayViewDidCancel(view)
    }

    func overlayViewDidConfirm(_ view: ScreenshotOverlayView) {
        sessionDelegate?.overlayViewDidConfirm(view)
    }

    func overlayViewDidRequestSave(_ view: ScreenshotOverlayView) {
        sessionDelegate?.overlayViewDidRequestSave(view)
    }

    func overlayViewDidRequestPin(_ view: ScreenshotOverlayView) {
        sessionDelegate?.overlayViewDidRequestPin(view)
    }
}
