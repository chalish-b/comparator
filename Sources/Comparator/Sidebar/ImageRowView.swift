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

        for view in [keyLabel, thumbnail, nameLabel, detailLabel, badgeStack] {
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
            nameLabel.trailingAnchor.constraint(equalTo: badgeStack.leadingAnchor, constant: -4),
            nameLabel.bottomAnchor.constraint(equalTo: centerYAnchor, constant: -1),

            detailLabel.leadingAnchor.constraint(equalTo: nameLabel.leadingAnchor),
            detailLabel.trailingAnchor.constraint(equalTo: nameLabel.trailingAnchor),
            detailLabel.topAnchor.constraint(equalTo: centerYAnchor, constant: 1),

            badgeStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            badgeStack.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func configure(index: Int, item: ImageItem, detail: String, badge rowBadge: Badge?) {
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
