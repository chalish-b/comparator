import AppKit

final class ImageRowView: NSTableCellView {
    static let identifier = NSUserInterfaceItemIdentifier("ImageRow")

    private let thumbnail = NSImageView()
    private let keyLabel = NSTextField(labelWithString: "")
    private let nameLabel = NSTextField(labelWithString: "")
    private let detailLabel = NSTextField(labelWithString: "")
    private let badge = NSTextField(labelWithString: "")

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

        for view in [keyLabel, thumbnail, nameLabel, detailLabel, badge] {
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
            nameLabel.trailingAnchor.constraint(equalTo: badge.leadingAnchor, constant: -4),
            nameLabel.bottomAnchor.constraint(equalTo: centerYAnchor, constant: -1),

            detailLabel.leadingAnchor.constraint(equalTo: nameLabel.leadingAnchor),
            detailLabel.trailingAnchor.constraint(equalTo: nameLabel.trailingAnchor),
            detailLabel.topAnchor.constraint(equalTo: centerYAnchor, constant: 1),

            badge.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            badge.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func configure(index: Int, item: ImageItem, detail: String, badge badgeText: String?) {
        keyLabel.stringValue = index < 9 ? "\(index + 1)" : ""
        thumbnail.image = item.thumbnail
        nameLabel.stringValue = item.name
        nameLabel.toolTip = item.url.path
        detailLabel.stringValue = detail
        detailLabel.textColor = item.error != nil ? .systemRed : .secondaryLabelColor
        badge.stringValue = badgeText ?? ""
    }
}
