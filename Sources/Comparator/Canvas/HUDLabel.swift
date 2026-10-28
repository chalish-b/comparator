import AppKit

/// A small translucent label drawn over the image: a glass capsule on macOS 26 and later,
/// a dark rounded rectangle before that.
final class HUDLabel: NSView {
    private let field = NSTextField(labelWithString: "")
    private var glass: NSView?
    private let symbol: NSImage?

    /// `symbol` names an SF Symbol shown before the text. `monospacedDigits` keeps the label
    /// steady while numbers change.
    init(
        fontSize: CGFloat,
        weight: NSFont.Weight = .regular,
        monospaced: Bool = false,
        monospacedDigits: Bool = false,
        symbol: String? = nil
    ) {
        self.symbol = symbol.map {
            NSImage(systemSymbolName: $0, accessibilityDescription: nil)!
                .withSymbolConfiguration(.init(pointSize: fontSize, weight: .medium))!
        }
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        isHidden = true

        field.font = if monospaced {
            .monospacedSystemFont(ofSize: fontSize, weight: weight)
        } else if monospacedDigits {
            .monospacedDigitSystemFont(ofSize: fontSize, weight: weight)
        } else {
            .systemFont(ofSize: fontSize, weight: weight)
        }
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

    var font: NSFont { field.font! }
    var textColor: NSColor { field.textColor! }

    var text: String? {
        get { isHidden ? nil : field.stringValue }
        set {
            guard let newValue, !newValue.isEmpty else {
                isHidden = true
                return
            }
            if let symbol {
                let attachment = NSTextAttachment()
                attachment.image = symbol
                let content = NSMutableAttributedString(attachment: attachment)
                content.append(NSAttributedString(string: "  " + newValue))
                attributedText = content
            } else {
                field.stringValue = newValue
                isHidden = false
            }
        }
    }

    /// Rich text; the label's font and colour fill in wherever the string sets none.
    var attributedText: NSAttributedString? {
        get { isHidden ? nil : field.attributedStringValue }
        set {
            guard let newValue, newValue.length > 0 else {
                isHidden = true
                return
            }
            let content = NSMutableAttributedString(attributedString: newValue)
            let whole = NSRange(location: 0, length: content.length)
            content.enumerateAttributes(in: whole) { attributes, range, _ in
                var filled = attributes
                if filled[.font] == nil { filled[.font] = font }
                if filled[.foregroundColor] == nil { filled[.foregroundColor] = textColor }
                content.setAttributes(filled, range: range)
            }
            field.attributedStringValue = content
            isHidden = false
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
