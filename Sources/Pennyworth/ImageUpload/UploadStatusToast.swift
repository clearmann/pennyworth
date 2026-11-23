import AppKit

/// Lightweight non-activating floating HUD shown near the top-right corner of the active screen.
@MainActor final class UploadStatusToast {
    enum Style {
        case success
        case error
        case info

        var symbolName: String {
            switch self {
            case .success: return "checkmark.circle.fill"
            case .error: return "exclamationmark.triangle.fill"
            case .info: return "icloud.and.arrow.up"
            }
        }

        var tintColor: NSColor {
            switch self {
            case .success: return .systemGreen
            case .error: return .systemOrange
            case .info: return .controlAccentColor
            }
        }
    }

    private var panel: NSPanel?
    private var dismissTimer: Timer?

    func show(title: String, detail: String?, style: Style, duration: TimeInterval = 3.2) {
        dismissTimer?.invalidate()
        let panel = ensurePanel()
        configureContent(in: panel, title: title, detail: detail, style: style)
        position(panel)
        panel.alphaValue = 1
        panel.orderFrontRegardless()

        dismissTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.dismiss()
            }
        }
    }

    func dismiss() {
        dismissTimer?.invalidate()
        dismissTimer = nil
        panel?.orderOut(nil)
    }

    private func ensurePanel() -> NSPanel {
        if let existing = panel {
            return existing
        }
        let created = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 64),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        created.isFloatingPanel = true
        created.level = .statusBar
        created.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        created.backgroundColor = .clear
        created.isOpaque = false
        created.hasShadow = true
        created.ignoresMouseEvents = true
        panel = created
        return created
    }

    private func configureContent(in panel: NSPanel, title: String, detail: String?, style: Style) {
        let container = NSVisualEffectView()
        container.material = .hudWindow
        container.blendingMode = .behindWindow
        container.state = .active
        container.wantsLayer = true
        container.layer?.cornerRadius = 12
        container.layer?.borderWidth = 1
        container.layer?.borderColor = NSColor.separatorColor.cgColor

        let icon = NSImageView()
        icon.image = NSImage(systemSymbolName: style.symbolName, accessibilityDescription: nil)
        icon.contentTintColor = style.tintColor
        icon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 18, weight: .semibold)
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.widthAnchor.constraint(equalToConstant: 24).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 24).isActive = true

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        titleLabel.textColor = .labelColor
        titleLabel.lineBreakMode = .byTruncatingTail

        let textStack = NSStackView(views: [titleLabel])
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 2

        if let detail, !detail.isEmpty {
            let detailLabel = NSTextField(wrappingLabelWithString: detail)
            detailLabel.font = .systemFont(ofSize: 11)
            detailLabel.textColor = .secondaryLabelColor
            detailLabel.maximumNumberOfLines = 2
            detailLabel.lineBreakMode = .byTruncatingMiddle
            textStack.addArrangedSubview(detailLabel)
        }

        let row = NSStackView(views: [icon, textStack])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 10
        row.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 14),
            row.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -14),
            row.topAnchor.constraint(equalTo: container.topAnchor, constant: 12),
            row.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -12),
            container.widthAnchor.constraint(greaterThanOrEqualToConstant: 240),
            container.widthAnchor.constraint(lessThanOrEqualToConstant: 360),
        ])

        panel.contentView = container
        container.layoutSubtreeIfNeeded()
        let fitting = container.fittingSize
        panel.setContentSize(NSSize(width: min(max(fitting.width, 240), 360), height: max(fitting.height, 52)))
    }

    private func position(_ panel: NSPanel) {
        let screen = NSScreen.screens.first(where: { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) })
            ?? NSScreen.main
        guard let frame = screen?.visibleFrame else { return }
        let size = panel.frame.size
        let origin = NSPoint(
            x: frame.maxX - size.width - 18,
            y: frame.maxY - size.height - 16
        )
        panel.setFrameOrigin(origin)
    }
}
