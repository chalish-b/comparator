import AppKit

/// A small translucent label drawn over the image.
final class HUDLabel: NSView {
    private let field = NSTextField(labelWithString: "")

    init(fontSize: CGFloat, weight: NSFont.Weight = .regular, monospaced: Bool = false) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.backgroundColor = NSColor(white: 0, alpha: 0.62).cgColor
        layer?.cornerRadius = 6
        isHidden = true

        field.font = monospaced
            ? .monospacedSystemFont(ofSize: fontSize, weight: weight)
            : .systemFont(ofSize: fontSize, weight: weight)
        field.textColor = .white
        field.maximumNumberOfLines = 0
        field.lineBreakMode = .byTruncatingMiddle
        field.translatesAutoresizingMaskIntoConstraints = false
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        addSubview(field)

        NSLayoutConstraint.activate([
            field.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            field.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            field.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            field.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    var text: String? {
        get { isHidden ? nil : field.stringValue }
        set {
            field.stringValue = newValue ?? ""
            isHidden = newValue?.isEmpty ?? true
        }
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

/// A view that hosts a layer tree owned by its superview.
final class LayerHostView: NSView {
    let root = CALayer()

    override init(frame: NSRect) {
        super.init(frame: frame)
        layer = root
        wantsLayer = true
        layerUsesCoreImageFilters = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
