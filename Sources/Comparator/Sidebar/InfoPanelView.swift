import AppKit

/// The Info section at the bottom of the sidebar: file and format details of the image shown,
/// or of both images side by side in split and difference views, with differing values
/// emphasized.
final class InfoPanelView: NSView {
    static let headerHeight: CGFloat = 28

    private struct Column: Equatable {
        let number: Int
        let name: String
    }

    private struct Row: Equatable {
        let label: String
        let values: [String]
    }

    private struct Content: Equatable {
        var columns: [Column] = []
        var rows: [Row] = []
    }

    private let imageSet: ComparisonSet
    private let header = InfoHeaderView()
    private let scrollView = NSScrollView()
    private let documentView = FlippedView()
    private let stack = NSStackView()
    private let placeholder = NSTextField(labelWithString: "No Image")
    private var content: Content?

    var isExpanded = true {
        didSet { header.isExpanded = isExpanded }
    }

    var onToggle: (() -> Void)? {
        get { header.onClick }
        set { header.onClick = newValue }
    }

    /// Called with the mouse-down event when a press on the header turns into a drag.
    var onHeaderDragStart: ((NSEvent) -> Void)? {
        get { header.onDragStart }
        set { header.onDragStart = newValue }
    }

    var onHeaderDrag: ((NSEvent) -> Void)? {
        get { header.onDrag }
        set { header.onDrag = newValue }
    }

    init(set: ComparisonSet) {
        imageSet = set
        super.init(frame: .zero)
        clipsToBounds = true

        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        documentView.addSubview(stack)
        documentView.translatesAutoresizingMaskIntoConstraints = false

        scrollView.documentView = documentView
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true

        placeholder.font = .systemFont(ofSize: 11)
        placeholder.textColor = .tertiaryLabelColor

        for view in [header, scrollView, placeholder] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }

        let clipView = scrollView.contentView
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: topAnchor),
            header.leadingAnchor.constraint(equalTo: leadingAnchor),
            header.trailingAnchor.constraint(equalTo: trailingAnchor),
            header.heightAnchor.constraint(equalToConstant: Self.headerHeight),

            scrollView.topAnchor.constraint(equalTo: header.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),

            documentView.topAnchor.constraint(equalTo: clipView.topAnchor),
            documentView.leadingAnchor.constraint(equalTo: clipView.leadingAnchor),
            documentView.widthAnchor.constraint(equalTo: clipView.widthAnchor),

            stack.topAnchor.constraint(equalTo: documentView.topAnchor, constant: 2),
            stack.leadingAnchor.constraint(equalTo: documentView.leadingAnchor, constant: 18),
            stack.trailingAnchor.constraint(equalTo: documentView.trailingAnchor, constant: -14),
            stack.bottomAnchor.constraint(equalTo: documentView.bottomAnchor, constant: -12),

            placeholder.centerXAnchor.constraint(equalTo: scrollView.centerXAnchor),
            placeholder.topAnchor.constraint(equalTo: scrollView.topAnchor, constant: 8),
        ])

        imageSet.observe { [weak self] change in
            if !change.isDisjoint(with: [.items, .content, .selection, .display]) { self?.update() }
        }
        update()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Content

    /// The images described: the current one, or both shown in split and difference views, in split order.
    private var shownItems: [ImageItem] {
        if imageSet.mode != .single, let pair = imageSet.splitPair { return [pair.first, pair.second] }
        return imageSet.current.map { [$0] } ?? []
    }

    private func update() {
        let items = shownItems
        let newContent = Content(
            columns: items.map { Column(number: (imageSet.index(of: $0) ?? 0) + 1, name: $0.name) },
            rows: Self.rows(for: items)
        )
        guard newContent != content else { return }
        content = newContent
        rebuild(newContent)
    }

    private static func rows(for items: [ImageItem]) -> [Row] {
        guard !items.isEmpty else { return [] }
        var rows: [Row] = []

        func add(_ label: String, optional: Bool = false, _ value: (ImageItem, ImageInfo) -> String?) {
            let values = items.map { item in item.info.flatMap { value(item, $0) } }
            if optional, values.allSatisfy({ $0 == nil }) { return }
            rows.append(Row(label: label, values: values.map { $0 ?? "—" }))
        }

        add("Format") { _, info in info.format }
        add("File size") { item, _ in
            item.stamp.map { ByteCountFormatter.string(fromByteCount: Int64($0.size), countStyle: .file) }
        }
        add("Dimensions") { item, _ in "\(Int(item.pixelSize.width))×\(Int(item.pixelSize.height))" }
        add("Megapixels") { item, _ in
            let megapixels = item.pixelSize.width * item.pixelSize.height / 1_000_000
            return String(format: megapixels < 1 ? "%.2f MP" : "%.1f MP", megapixels)
        }
        if items.count == 2 {
            let widths = items.map(\.pixelSize.width)
            if let smallest = widths.min(), smallest > 0, items.allSatisfy(\.isLoaded), widths[0] != widths[1] {
                add("Scale") { item, _ in SidebarViewController.format(ratio: item.pixelSize.width / smallest) }
            }
        }
        add("Color") { _, info in
            var parts = [info.colorModel ?? "Unknown"]
            if let depth = info.bitDepth { parts.append("\(depth)-bit") }
            if info.isIndexed { parts.append("indexed") }
            return parts.joined(separator: " · ")
        }
        add("Alpha") { _, info in info.hasAlpha ? "Yes" : "No" }
        add("Profile") { _, info in info.profile ?? "None" }
        add("DPI", optional: true) { _, info in
            info.dpi.map { dpi in
                dpi.width == dpi.height ? format(dpi.width) : "\(format(dpi.width)) × \(format(dpi.height))"
            }
        }
        add("Modified") { item, _ in item.stamp.map { format($0.modified) } }
        add("Camera", optional: true) { _, info in info.camera }
        add("Lens", optional: true) { _, info in info.lens }
        add("Taken", optional: true) { _, info in info.dateTaken.map(format) }
        return rows
    }

    private static func format(_ number: Double) -> String {
        number == number.rounded() ? String(Int(number)) : String(format: "%.1f", number)
    }

    private static func format(_ date: Date) -> String {
        let style = Date.FormatStyle.dateTime.month(.abbreviated).day().hour().minute()
        let sameYear = Calendar.current.isDate(date, equalTo: .now, toGranularity: .year)
        return date.formatted(sameYear ? style : style.year())
    }

    // MARK: - Views

    private static let labelWidth: CGFloat = 80
    private static let fontSize: CGFloat = 12

    private func rebuild(_ content: Content) {
        for view in stack.arrangedSubviews { view.removeFromSuperview() }
        placeholder.isHidden = !content.columns.isEmpty
        let isPair = content.columns.count == 2

        if isPair {
            let names = content.columns.map { column -> NSView in
                let number = Self.label("\(column.number)", font: .monospacedDigitSystemFont(ofSize: Self.fontSize, weight: .semibold))
                number.textColor = .secondaryLabelColor
                number.setContentCompressionResistancePriority(.required, for: .horizontal)
                number.setContentHuggingPriority(.required, for: .horizontal)
                let name = Self.label(column.name, font: .systemFont(ofSize: Self.fontSize, weight: .medium))
                name.lineBreakMode = .byTruncatingMiddle
                name.toolTip = column.name
                let pair = NSStackView(views: [number, name])
                pair.spacing = 5
                pair.alignment = .firstBaseline
                return pair
            }
            stack.setCustomSpacing(7, after: addRow(label: nil, values: names))

            let separator = NSBox()
            separator.boxType = .separator
            stack.addArrangedSubview(separator)
            separator.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
            stack.setCustomSpacing(7, after: separator)
        }

        for row in content.rows {
            let differs = isPair && Set(row.values).count > 1
            let values = row.values.map { value -> NSView in
                let label = Self.label(value, font: .monospacedDigitSystemFont(ofSize: Self.fontSize, weight: differs ? .semibold : .regular))
                label.textColor = isPair && !differs ? .secondaryLabelColor : .labelColor
                label.toolTip = value
                return label
            }
            addRow(label: row.label, values: values)
        }
    }

    /// Adds a row with a fixed-width label and the values sharing the remaining width equally.
    @discardableResult
    private func addRow(label text: String?, values: [NSView]) -> NSView {
        let label = Self.label(text ?? "", font: .systemFont(ofSize: Self.fontSize))
        label.textColor = .secondaryLabelColor
        label.widthAnchor.constraint(equalToConstant: Self.labelWidth).isActive = true

        let valueStack = NSStackView(views: values)
        valueStack.distribution = .fillEqually
        valueStack.alignment = .firstBaseline
        valueStack.spacing = 14
        valueStack.setHuggingPriority(.defaultLow, for: .horizontal)

        let row = NSStackView(views: [label, valueStack])
        row.distribution = .fill
        row.spacing = 8
        row.alignment = .firstBaseline
        stack.addArrangedSubview(row)
        row.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        return row
    }

    private static func label(_ text: String, font: NSFont) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = font
        label.lineBreakMode = .byTruncatingTail
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return label
    }
}

/// The Info section's title row. Clicking it expands or collapses the section, and dragging it
/// resizes the section.
private final class InfoHeaderView: NSView {
    var onClick: (() -> Void)?
    var onDragStart: ((NSEvent) -> Void)?
    var onDrag: ((NSEvent) -> Void)?
    private var mouseDownEvent: NSEvent?
    private var isDragging = false
    var isExpanded = true {
        didSet { updateChevron() }
    }

    private let title = NSTextField(labelWithString: "Info")
    private let chevron = NSImageView()

    init() {
        super.init(frame: .zero)
        title.font = .systemFont(ofSize: 11, weight: .semibold)
        title.textColor = .secondaryLabelColor
        chevron.symbolConfiguration = .init(pointSize: 10, weight: .semibold)
        chevron.contentTintColor = .tertiaryLabelColor
        for view in [title, chevron] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            title.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 18),
            title.centerYAnchor.constraint(equalTo: centerYAnchor),
            chevron.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            chevron.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        updateChevron()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    private func updateChevron() {
        chevron.image = NSImage(
            systemSymbolName: isExpanded ? "chevron.down" : "chevron.right",
            accessibilityDescription: isExpanded ? "Collapse" : "Expand"
        )
    }

    override func mouseDown(with event: NSEvent) {
        mouseDownEvent = event
        isDragging = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard let mouseDownEvent else { return }
        if !isDragging {
            guard abs(event.locationInWindow.y - mouseDownEvent.locationInWindow.y) >= 3 else { return }
            isDragging = true
            onDragStart?(mouseDownEvent)
        }
        onDrag?(event)
    }

    override func mouseUp(with event: NSEvent) {
        defer { mouseDownEvent = nil }
        if !isDragging, bounds.contains(convert(event.locationInWindow, from: nil)) { onClick?() }
    }
}

private final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}
