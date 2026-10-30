import AppKit

final class ImageRowView: NSTableCellView {
    /// A marker at the row's trailing edge: a shortcut that leads to the image, or an SF Symbol
    /// for where it's shown.
    enum Badge {
        case key(String)
        case symbol(String)
    }

    static let identifier = NSUserInterfaceItemIdentifier("ImageRow")

    private let thumbnail = NSImageView()
    private let keyLabel = NSTextField(labelWithString: "")
    private let nameLabel = NSTextField(labelWithString: "")
    private let detailLabel = NSTextField(labelWithString: "")
    private let badge = NSTextField(labelWithString: "")
    private let badgeSymbol = NSImageView()
    private let badgeStack = NSStackView()
    private let pinButton = NSButton()
    private var isPinned = false
    private var isHovered = false {
        didSet { updatePinButton() }
    }
    /// Called when the pin button is clicked.
    var onTogglePin: (() -> Void)?

    init() {
        super.init(frame: .zero)
        identifier = Self.identifier

        thumbnail.imageScaling = .scaleProportionallyUpOrDown
        thumbnail.wantsLayer = true
        thumbnail.layer?.cornerRadius = 4
        thumbnail.layer?.masksToBounds = true

        keyLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .semibold)
        keyLabel.textColor = .secondaryLabelColor
        keyLabel.alignment = .center

        nameLabel.font = .systemFont(ofSize: 13, weight: .medium)
        nameLabel.lineBreakMode = .byTruncatingMiddle
        nameLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        detailLabel.font = .systemFont(ofSize: 11)
        detailLabel.textColor = .secondaryLabelColor
        detailLabel.lineBreakMode = .byTruncatingTail
        detailLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        badge.font = .systemFont(ofSize: 11, weight: .bold)
        badge.textColor = .controlAccentColor
        badge.alignment = .right
        badge.setContentHuggingPriority(.required, for: .horizontal)
        badge.setContentCompressionResistancePriority(.required, for: .horizontal)

        badgeSymbol.symbolConfiguration = .init(pointSize: 12, weight: .medium)
        badgeSymbol.contentTintColor = .secondaryLabelColor
        badgeSymbol.setContentHuggingPriority(.required, for: .horizontal)
        badgeSymbol.setContentCompressionResistancePriority(.required, for: .horizontal)
        badgeStack.addArrangedSubview(badge)
        badgeStack.addArrangedSubview(badgeSymbol)
        badgeStack.setHuggingPriority(.required, for: .horizontal)

        pinButton.isBordered = false
        pinButton.imagePosition = .imageOnly
        pinButton.symbolConfiguration = .init(pointSize: 11, weight: .medium)
        pinButton.contentTintColor = .secondaryLabelColor
        pinButton.target = self
        pinButton.action = #selector(pinClicked)

        for view in [keyLabel, thumbnail, nameLabel, detailLabel, pinButton, badgeStack] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }

        NSLayoutConstraint.activate([
            keyLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            keyLabel.widthAnchor.constraint(equalToConstant: 14),
            keyLabel.centerYAnchor.constraint(equalTo: centerYAnchor),

            thumbnail.leadingAnchor.constraint(equalTo: keyLabel.trailingAnchor, constant: 4),
            thumbnail.centerYAnchor.constraint(equalTo: centerYAnchor),
            thumbnail.widthAnchor.constraint(equalToConstant: 44),
            thumbnail.heightAnchor.constraint(equalToConstant: 44),

            nameLabel.leadingAnchor.constraint(equalTo: thumbnail.trailingAnchor, constant: 8),
            nameLabel.trailingAnchor.constraint(equalTo: pinButton.leadingAnchor, constant: -4),
            nameLabel.bottomAnchor.constraint(equalTo: centerYAnchor, constant: -1),

            detailLabel.leadingAnchor.constraint(equalTo: nameLabel.leadingAnchor),
            detailLabel.trailingAnchor.constraint(equalTo: nameLabel.trailingAnchor),
            detailLabel.topAnchor.constraint(equalTo: centerYAnchor, constant: 1),

            pinButton.trailingAnchor.constraint(equalTo: badgeStack.leadingAnchor, constant: -4),
            pinButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            pinButton.widthAnchor.constraint(equalToConstant: 18),

            badgeStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            badgeStack.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func configure(index: Int, item: ImageItem, detail: String, badge rowBadge: Badge?, pinned: Bool) {
        isPinned = pinned
        updatePinButton()
        keyLabel.stringValue = index < 9 ? "\(index + 1)" : ""
        thumbnail.image = item.thumbnail
        nameLabel.stringValue = item.name
        nameLabel.toolTip = item.url.path
        detailLabel.stringValue = detail
        detailLabel.textColor = item.error != nil ? .systemRed : .secondaryLabelColor
        badge.isHidden = true
        badgeSymbol.isHidden = true
        switch rowBadge {
        case .key(let text):
            badge.stringValue = text
            badge.isHidden = false
        case .symbol(let name):
            badgeSymbol.image = NSImage(systemSymbolName: name, accessibilityDescription: nil)
            badgeSymbol.isHidden = false
        case nil:
            break
        }
    }

    // MARK: - Pin

    /// The pin shows on the pinned image, and on any other row while the pointer is over it.
    private func updatePinButton() {
        pinButton.isHidden = !isPinned && !isHovered
        pinButton.image = NSImage(systemSymbolName: isPinned ? "pin.fill" : "pin", accessibilityDescription: isPinned ? "Unpin" : "Pin")
        pinButton.toolTip = isPinned ? "Unpin" : "Pin"
    }

    @objc private func pinClicked() {
        onTogglePin?()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(
            rect: .zero, options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect], owner: self
        ))
        if let window {
            isHovered = bounds.contains(convert(window.mouseLocationOutsideOfEventStream, from: nil))
        }
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
    }
}

/// A sidebar row that can mark its image as shown on the canvas without being selected, with a
/// faint fill shaped like the selection.
final class ImageTableRowView: NSTableRowView {
    var isShown = false {
        didSet { if isShown != oldValue { needsDisplay = true } }
    }

    override func drawBackground(in dirtyRect: NSRect) {
        super.drawBackground(in: dirtyRect)
        guard isShown, !isSelected else { return }
        NSColor.unemphasizedSelectedContentBackgroundColor.withAlphaComponent(0.45).setFill()
        NSBezierPath(roundedRect: bounds.insetBy(dx: 10, dy: 0), xRadius: 5, yRadius: 5).fill()
    }
}
