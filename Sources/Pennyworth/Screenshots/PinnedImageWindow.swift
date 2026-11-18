import AppKit

/// A cropped screenshot view used by a pinned image panel.
final class PinnedImageView: NSView {
    var image: CGImage? {
        didSet { needsDisplay = true }
    }
    var imagePointSize: CGSize = .zero
    var onRequestClose: (() -> Void)?
    var onScroll: ((NSEvent) -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let image, bounds.width > 0, bounds.height > 0 else { return }
        let scale = min(bounds.width / imagePointSize.width,
                        bounds.height / imagePointSize.height)
        guard scale.isFinite, scale > 0 else { return }
        let drawSize = CGSize(width: imagePointSize.width * scale,
                              height: imagePointSize.height * scale)
        let drawRect = CGRect(x: bounds.midX - drawSize.width / 2,
                              y: bounds.midY - drawSize.height / 2,
                              width: drawSize.width, height: drawSize.height)
        let context = NSGraphicsContext.current?.cgContext
        context?.interpolationQuality = .high
        context?.draw(image, in: drawRect)
    }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount >= 2 {
            onRequestClose?()
        } else {
            window?.performDrag(with: event)
        }
    }

    override func scrollWheel(with event: NSEvent) {
        onScroll?(event)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onRequestClose?()
        } else {
            super.keyDown(with: event)
        }
    }

    override func cancelOperation(_ sender: Any?) {
        onRequestClose?()
    }
}

/// A floating, nonactivating panel that displays only the supplied cropped image.
final class PinnedImageWindow: NSPanel {
    let imageID: UUID
    private(set) var screenshot: RenderedScreenshot?
    private(set) var zoom: CGFloat = 1
    var onRequestClose: ((UUID) -> Void)?

    private let basePointSize: CGSize
    private let pinnedImageView: PinnedImageView

    var decodedByteCount: Int {
        guard let image = screenshot?.cgImage else { return 0 }
        return image.bytesPerRow * image.height
    }

    init(screenshot: RenderedScreenshot, frame: CGRect, imageID: UUID = UUID()) {
        self.imageID = imageID
        self.screenshot = screenshot
        self.basePointSize = screenshot.pointSize
        self.pinnedImageView = PinnedImageView(frame: CGRect(origin: .zero, size: frame.size))
        super.init(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        hidesOnDeactivate = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isReleasedWhenClosed = false

        pinnedImageView.image = screenshot.cgImage
        pinnedImageView.imagePointSize = screenshot.pointSize
        pinnedImageView.autoresizingMask = [.width, .height]
        pinnedImageView.onRequestClose = { [weak self] in self?.requestClose() }
        pinnedImageView.onScroll = { [weak self] event in self?.handleScroll(event) }
        contentView = pinnedImageView
        initialFirstResponder = pinnedImageView
    }

    override var canBecomeKey: Bool { true }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            requestClose()
        } else {
            super.keyDown(with: event)
        }
    }

    override func cancelOperation(_ sender: Any?) {
        requestClose()
    }

    func setZoom(_ newZoom: CGFloat) {
        let clampedZoom = min(max(newZoom, 0.1), 8.0)
        let center = CGPoint(x: frame.midX, y: frame.midY)
        let size = CGSize(width: basePointSize.width * clampedZoom,
                          height: basePointSize.height * clampedZoom)
        zoom = clampedZoom
        setFrame(CGRect(x: center.x - size.width / 2, y: center.y - size.height / 2,
                        width: size.width, height: size.height), display: true)
    }

    func releaseImage() {
        pinnedImageView.image = nil
        screenshot = nil
    }

    private func requestClose() {
        onRequestClose?(imageID)
    }

    private func handleScroll(_ event: NSEvent) {
        guard event.scrollingDeltaY != 0 else { return }
        let direction: CGFloat = event.scrollingDeltaY > 0 ? 1 : -1
        setZoom(zoom * pow(1.1, direction))
    }
}
