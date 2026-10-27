import AppKit

/// A small translucent label drawn over the image: a glass capsule on macOS 26 and later,
/// a dark rounded rectangle before that.
final class HUDLabel: NSView {
    private let field = NSTextField(labelWithString: "")
    private var glass: NSView?

    init(fontSize: CGFloat, weight: NSFont.Weight = .regular, monospaced: Bool = false) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        isHidden = true

        field.font = monospaced
            ? .monospacedSystemFont(ofSize: fontSize, weight: weight)
            : .systemFont(ofSize: fontSize, weight: weight)
        field.maximumNumberOfLines = 0
        field.lineBreakMode = .byTruncatingMiddle
        field.translatesAutoresizingMaskIntoConstraints = false
        // Above the glass view's own content hugging so the text sets the label's width, and
        // below windowSizeStayPut so long text truncates instead of widening the window.
        field.setContentCompressionResistancePriority(.windowSizeStayPut - 1, for: .horizontal)

        let padding: NSSize
        if #available(macOS 26, *) {
            let glass = NSGlassEffectView()
            glass.translatesAutoresizingMaskIntoConstraints = false
            addSubview(glass)
            NSLayoutConstraint.activate([
                glass.leadingAnchor.constraint(equalTo: leadingAnchor),
                glass.trailingAnchor.constraint(equalTo: trailingAnchor),
                glass.topAnchor.constraint(equalTo: topAnchor),
                glass.bottomAnchor.constraint(equalTo: bottomAnchor),
            ])
            self.glass = glass
            field.textColor = .labelColor
            padding = NSSize(width: 12, height: 6)
        } else {
            wantsLayer = true
            layer?.backgroundColor = NSColor(white: 0, alpha: 0.62).cgColor
            layer?.cornerRadius = 6
            field.textColor = .white
            padding = NSSize(width: 8, height: 4)
        }
        addSubview(field)

        NSLayoutConstraint.activate([
            field.leadingAnchor.constraint(equalTo: leadingAnchor, constant: padding.width),
            field.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -padding.width),
            field.topAnchor.constraint(equalTo: topAnchor, constant: padding.height),
            field.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -padding.height),
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

    override func layout() {
        super.layout()
        // Capsule-shaped for one line, rounded corners for taller text like the shortcuts list.
        if #available(macOS 26, *), let glass = glass as? NSGlassEffectView {
            glass.cornerRadius = min(bounds.height / 2, 16)
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
