import AppKit

@MainActor final class PinnedImageManager: NSObject, NSWindowDelegate {
    static let maxPinnedImages = 20
    static let maxDecodedBytes = 512 * 1024 * 1024

    private(set) var windows: [PinnedImageWindow] = []
    private let decodedByteBudget: Int

    override init() {
        self.decodedByteBudget = Self.maxDecodedBytes
        super.init()
    }

    init(maxDecodedBytes: Int) {
        self.decodedByteBudget = max(0, maxDecodedBytes)
        super.init()
    }

    var estimatedDecodedBytes: Int {
        windows.reduce(0) { $0 + $1.decodedByteCount }
    }

    @discardableResult func pin(_ screenshot: RenderedScreenshot) throws -> UUID {
        let image = screenshot.cgImage
        let additionalBytes = image.bytesPerRow * image.height
        if windows.count >= Self.maxPinnedImages || estimatedDecodedBytes + additionalBytes > decodedByteBudget {
            throw ScreenshotError.pinLimitExceeded
        }

        let visibleFrame = screenUnderMouse()?.visibleFrame ?? CGRect(x: 0, y: 0, width: 800, height: 600)
        let frame = Self.cascadingFrame(index: windows.count, pointSize: screenshot.pointSize,
                                        visibleFrame: visibleFrame)
        let window = PinnedImageWindow(screenshot: screenshot, frame: frame)
        window.delegate = self
        window.onRequestClose = { [weak self] id in self?.close(id: id) }
        windows.append(window)
        window.orderFront(nil)
        return window.imageID
    }

    func close(id: UUID) {
        guard let window = windows.first(where: { $0.imageID == id }) else { return }
        windows.removeAll { $0.imageID == id }
        detach(window)
        window.orderOut(nil)
    }

    func closeAll() {
        let openWindows = windows
        windows = []
        openWindows.forEach(detach)
        openWindows.forEach { $0.orderOut(nil) }
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? PinnedImageWindow,
              windows.contains(where: { $0.imageID == window.imageID }) else { return }
        windows.removeAll { $0.imageID == window.imageID }
        detach(window)
    }

    static func cascadingFrame(index: Int, pointSize: CGSize, visibleFrame: CGRect) -> CGRect {
        let offset = CGFloat(max(0, index)) * 24
        let proposedX = visibleFrame.midX - pointSize.width / 2 + offset
        let proposedY = visibleFrame.midY - pointSize.height / 2 - offset
        let maxX = max(visibleFrame.minX, visibleFrame.maxX - pointSize.width)
        let maxY = max(visibleFrame.minY, visibleFrame.maxY - pointSize.height)
        let x = min(max(proposedX, visibleFrame.minX), maxX)
        let y = min(max(proposedY, visibleFrame.minY), maxY)
        return CGRect(x: x, y: y, width: pointSize.width, height: pointSize.height)
    }

    private func screenUnderMouse() -> NSScreen? {
        let mouseLocation = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(mouseLocation) } ?? NSScreen.main
    }

    private func detach(_ window: PinnedImageWindow) {
        window.onRequestClose = nil
        window.delegate = nil
        window.releaseImage()
    }
}
