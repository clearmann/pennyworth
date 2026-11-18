import AppKit

@MainActor final class ClipboardImagePreviewView: NSView {
    static let preferredWidth: CGFloat = 280

    private let cardContainer = NSView()
    private let imageView = NSImageView()
    private let dimensionsBadge = KeycapBadgeView(style: .neutral, monospaced: true)

    init() {
        super.init(frame: .zero)
        cardContainer.translatesAutoresizingMaskIntoConstraints = false
        cardContainer.wantsLayer = true
        cardContainer.layer?.cornerRadius = 12
        cardContainer.layer?.borderWidth = 1
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.imageAlignment = .alignCenter
        imageView.identifier = NSUserInterfaceItemIdentifier("clipboard.imagePreview")
        imageView.setAccessibilityIdentifier("clipboard.imagePreview")
        imageView.setAccessibilityLabel(L10n.tr("clipboard.image_preview"))
        addSubview(cardContainer)
        cardContainer.addSubview(imageView)
        cardContainer.addSubview(dimensionsBadge)
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: Self.preferredWidth),
            cardContainer.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            cardContainer.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            cardContainer.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            cardContainer.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6),
            imageView.topAnchor.constraint(equalTo: cardContainer.topAnchor, constant: 12),
            imageView.leadingAnchor.constraint(equalTo: cardContainer.leadingAnchor, constant: 12),
            imageView.trailingAnchor.constraint(equalTo: cardContainer.trailingAnchor, constant: -12),
            imageView.bottomAnchor.constraint(equalTo: dimensionsBadge.topAnchor, constant: -10),
            dimensionsBadge.centerXAnchor.constraint(equalTo: cardContainer.centerXAnchor),
            dimensionsBadge.bottomAnchor.constraint(equalTo: cardContainer.bottomAnchor, constant: -12),
        ])
        isHidden = true
        applyAppearanceColors()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyAppearanceColors()
    }

    func update(with item: ClipboardItem?) {
        guard case .image(let image, let size)? = item?.content else {
            imageView.image = nil
            dimensionsBadge.update(text: "")
            isHidden = true
            return
        }
        imageView.image = image
        dimensionsBadge.update(text: "\(Int(size.width)) × \(Int(size.height))", style: .neutral)
        isHidden = false
    }

    private func applyAppearanceColors() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            cardContainer.layer?.backgroundColor = PennyworthTheme.surfaceCard.cgColor
            cardContainer.layer?.borderColor = PennyworthTheme.borderHairline.cgColor
        }
    }
}
