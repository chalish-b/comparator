import AppKit

/// Stacks the image list above the Info section, with a separator between them that can be
/// dragged to resize the section.
final class SidebarSplitView: NSView {
    static let minimumTopHeight: CGFloat = 60

    private let top: NSView
    private let bottom: NSView
    private let separator = NSBox()
    private let handle = DividerHandle()

    /// The bottom view's height, shrunk when needed to leave the top view its minimum.
    var bottomHeight: CGFloat {
        didSet { needsLayout = true }
    }
    var minimumBottomHeight: CGFloat {
        didSet { needsLayout = true }
    }
    /// Called while the divider is dragged, with the bottom height it's dragged to.
    var onDrag: ((CGFloat) -> Void)?
    private var grabOffset: CGFloat = 0

    init(top: NSView, bottom: NSView, bottomHeight: CGFloat, minimumBottomHeight: CGFloat) {
        self.top = top
        self.bottom = bottom
        self.bottomHeight = bottomHeight
        self.minimumBottomHeight = minimumBottomHeight
        super.init(frame: NSRect(x: 0, y: 0, width: 300, height: 600))
        separator.boxType = .separator
        handle.onMouseDown = { [weak self] event in self?.beginDividerDrag(with: event) }
        handle.onMouseDragged = { [weak self] event in self?.continueDividerDrag(with: event) }
        for view in [top, bottom, separator, handle] {
            addSubview(view)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    /// The largest bottom height that leaves the top view its minimum.
    var maximumBottomHeight: CGFloat {
        max(minimumBottomHeight, bounds.height - Self.minimumTopHeight)
    }

    override func layout() {
        super.layout()
        let height = min(max(bottomHeight, minimumBottomHeight), maximumBottomHeight)
        let topHeight = max(0, bounds.height - height)
        top.frame = NSRect(x: 0, y: 0, width: bounds.width, height: topHeight)
        bottom.frame = NSRect(x: 0, y: topHeight, width: bounds.width, height: height)
        separator.frame = NSRect(x: 0, y: topHeight, width: bounds.width, height: 1)
        handle.frame = NSRect(x: 0, y: topHeight - 3, width: bounds.width, height: 7)
        window?.invalidateCursorRects(for: handle)
    }

    /// Starts dragging the divider from the mouse-down `event`, keeping the divider's distance
    /// to the pointer. Other views can start a drag too, like the bottom view's header.
    func beginDividerDrag(with event: NSEvent) {
        grabOffset = convert(event.locationInWindow, from: nil).y - top.frame.maxY
    }

    func continueDividerDrag(with event: NSEvent) {
        let y = convert(event.locationInWindow, from: nil).y - grabOffset
        onDrag?(bounds.height - y)
    }
}

/// The strip over the separator that shows the resize cursor and reports drags.
private final class DividerHandle: NSView {
    var onMouseDown: ((NSEvent) -> Void)?
    var onMouseDragged: ((NSEvent) -> Void)?

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .resizeUpDown)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        onMouseDown?(event)
    }

    override func mouseDragged(with event: NSEvent) {
        onMouseDragged?(event)
    }
}
