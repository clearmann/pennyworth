import AppKit

/// Transparent overlay installed inside `NSStatusBarButton` to accept Finder file drops
/// without interfering with normal menu-bar clicks.
final class StatusBarDropView: NSView {
    var onDragHoverChanged: ((Bool) -> Void)?
    var onDropFiles: (([URL]) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.fileURL])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func mouseDown(with event: NSEvent) {
        superview?.mouseDown(with: event)
    }

    override func rightMouseDown(with event: NSEvent) {
        superview?.rightMouseDown(with: event)
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        let urls = extractFileURLs(from: sender.draggingPasteboard)
        guard !urls.isEmpty else { return [] }
        onDragHoverChanged?(true)
        return .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        onDragHoverChanged?(false)
    }

    override func draggingEnded(_ sender: NSDraggingInfo) {
        onDragHoverChanged?(false)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        onDragHoverChanged?(false)
        let urls = extractFileURLs(from: sender.draggingPasteboard)
        guard !urls.isEmpty else { return false }
        onDropFiles?(urls)
        return true
    }

    func extractFileURLs(from pasteboard: NSPasteboard) -> [URL] {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        if let objects = pasteboard.readObjects(forClasses: [NSURL.self], options: options) as? [URL] {
            return objects.filter(\.isFileURL)
        }
        return []
    }
}
