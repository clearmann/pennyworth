import AppKit

@MainActor final class ClipboardImagePreviewView: NSView {
    static let preferredWidth: CGFloat = 280

    private let imageView = NSImageView()
    private let dimensionsLabel = NSTextField(labelWithString: "")

    init() {
        super.init(frame: .zero)
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.imageAlignment = .alignCenter
        imageView.identifier = NSUserInterfaceItemIdentifier("clipboard.imagePreview")
        imageView.setAccessibilityIdentifier("clipboard.imagePreview")
        imageView.setAccessibilityLabel(L10n.tr("clipboard.image_preview"))
        dimensionsLabel.translatesAutoresizingMaskIntoConstraints = false
        dimensionsLabel.font = .systemFont(ofSize: 12)
        dimensionsLabel.textColor = .secondaryLabelColor
        dimensionsLabel.alignment = .center
        addSubview(imageView)
        addSubview(dimensionsLabel)
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: Self.preferredWidth),
            imageView.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            imageView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            imageView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            imageView.bottomAnchor.constraint(equalTo: dimensionsLabel.topAnchor, constant: -10),
            dimensionsLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            dimensionsLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            dimensionsLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12),
        ])
        isHidden = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func update(with item: ClipboardItem?) {
        guard case .image(let image, let size)? = item?.content else {
            imageView.image = nil
            dimensionsLabel.stringValue = ""
            isHidden = true
            return
        }
        imageView.image = image
        dimensionsLabel.stringValue = "\(Int(size.width))×\(Int(size.height))"
        isHidden = false
    }
}
