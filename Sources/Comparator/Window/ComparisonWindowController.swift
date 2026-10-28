import AppKit

/// A window (or tab) showing one comparison set: the image list on the left, the canvas on the right.
final class ComparisonWindowController: NSWindowController, NSWindowDelegate, NSToolbarDelegate {
    let imageSet = ComparisonSet()
    let canvas: CanvasView
    var onClose: (() -> Void)?

    private let modeControl = ToolbarSegments(
        symbols: ["rectangle", "rectangle.split.2x1", "circle.lefthalf.filled"],
        toolTips: ["Single", "Split (S). Click again to rotate (⇧S)", "Difference (D)"],
        trackingMode: .selectOne
    )
    private let noiseControl = ToolbarSegments(
        symbols: ["waveform.path"],
        toolTips: ["Noise (N)"],
        trackingMode: .selectAny
    )
    private let filterControl = ToolbarSegments(
        symbols: ["square.grid.3x3"],
        toolTips: ["Pixels (P)"],
        trackingMode: .selectAny
    )

    init() {
        canvas = CanvasView(set: imageSet)

        let canvasController = NSViewController()
        canvasController.view = canvas

        let sidebar = NSSplitViewItem(sidebarWithViewController: SidebarViewController(set: imageSet))
        sidebar.minimumThickness = 200
        sidebar.maximumThickness = 520
        let content = NSSplitViewItem(viewController: canvasController)
        content.minimumThickness = 300
        if #available(macOS 26, *) {
            // The canvas runs under the floating sidebar and keeps its HUD and fit within the safe area.
            content.automaticallyAdjustsSafeAreaInsets = true
        }

        let split = NSSplitViewController()
        split.addSplitViewItem(sidebar)
        split.addSplitViewItem(content)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1280, height: 820),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = split
        window.setContentSize(NSSize(width: 1280, height: 820))
        split.view.layoutSubtreeIfNeeded()
        split.splitView.setPosition(300, ofDividerAt: 0)
        split.splitView.autosaveName = "SidebarWidth"
        window.minSize = NSSize(width: 560, height: 360)
        window.tabbingMode = .preferred
        window.tabbingIdentifier = "ImageSet"
        window.isReleasedWhenClosed = false
        window.initialFirstResponder = canvas
        window.center()
        window.setFrameAutosaveName("ComparisonWindow")

        super.init(window: window)
        window.delegate = self

        modeControl.target = self
        modeControl.action = #selector(modeChanged(_:))
        noiseControl.target = self
        noiseControl.action = #selector(noiseChanged(_:))
        filterControl.target = self
        filterControl.action = #selector(filterChanged(_:))

        let toolbar = NSToolbar(identifier: "ComparisonToolbar")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        window.toolbar = toolbar
        window.toolbarStyle = .unified

        imageSet.observe { [weak self] _ in self?.update() }
        update()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    private func update() {
        guard let window else { return }
        if let first = imageSet.items.first {
            let others = imageSet.items.count - 1
            window.title = others > 0 ? "\(first.name) + \(others) more" : first.name
        } else {
            window.title = "New Set"
        }
        modeControl.setSymbol(imageSet.splitLayout == .sideBySide ? "rectangle.split.2x1" : "rectangle.split.1x2", forSegment: 1)
        modeControl.selectedSegment = switch imageSet.mode {
        case .single: 0
        case .split: 1
        case .difference: 2
        }
        filterControl.setSelected(imageSet.pixelated, forSegment: 0)
        noiseControl.setSelected(imageSet.noiseView, forSegment: 0)
    }

    func apply(_ request: OpenRequest) {
        imageSet.add(request.files)
        for number in request.show {
            imageSet.select(index: number - 1)
        }
        if let layout = request.splitLayout { imageSet.splitLayout = layout }
        imageSet.splitSwapped = request.swapped
        if let divider = request.divider { imageSet.splitPosition = divider }
        if let pixelated = request.pixelated { imageSet.pixelated = pixelated }
        if let mode = request.mode { imageSet.mode = mode }
        canvas.showView(zoomPercent: request.zoomPercent, center: request.center)
    }

    @objc private func modeChanged(_ sender: NSSegmentedControl) {
        if sender.selectedSegment == 1, imageSet.mode == .split {
            canvas.rotateSplit(sender)
            window?.makeFirstResponder(canvas)
            return
        }
        imageSet.mode = switch sender.selectedSegment {
        case 1: .split
        case 2: .difference
        default: .single
        }
        window?.makeFirstResponder(canvas)
    }

    @objc private func noiseChanged(_ sender: NSSegmentedControl) {
        canvas.toggleNoiseView(sender)
        window?.makeFirstResponder(canvas)
    }

    @objc private func filterChanged(_ sender: NSSegmentedControl) {
        canvas.togglePixelated(sender)
        window?.makeFirstResponder(canvas)
    }

    @objc func addImages(_ sender: Any?) {
        guard let window else { return }
        let panel = NSOpenPanel.forImages()
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK else { return }
            self?.imageSet.add(ImageFiles.expand(panel.urls))
        }
    }

    override func newWindowForTab(_ sender: Any?) {
        guard let delegate = NSApp.delegate as? AppDelegate, let window else { return }
        let controller = delegate.makeController()
        if let newWindow = controller.window {
            window.addTabbedWindow(newWindow, ordered: .above)
            newWindow.makeKeyAndOrderFront(nil)
        }
    }

    func windowWillClose(_ notification: Notification) {
        imageSet.close()
        onClose?()
    }

    // MARK: - Toolbar

    private static let modeItem = NSToolbarItem.Identifier("mode")
    private static let filterItem = NSToolbarItem.Identifier("filter")
    private static let noiseItem = NSToolbarItem.Identifier("noise")

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.toggleSidebar, .sidebarTrackingSeparator, .flexibleSpace, Self.modeItem, .space, Self.noiseItem, .space, Self.filterItem]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }

    func toolbar(
        _ toolbar: NSToolbar,
        itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        let item = NSToolbarItem(itemIdentifier: itemIdentifier)
        switch itemIdentifier {
        case Self.modeItem:
            item.view = modeControl
            item.label = "View"
        case Self.noiseItem:
            item.view = noiseControl
            item.label = "Noise"
        case Self.filterItem:
            item.view = filterControl
            item.label = "Pixels"
        default:
            return nil
        }
        return item
    }
}

/// A toolbar segmented control of SF Symbols with a tooltip per segment. Segments share the
/// width equally, and each tooltip covers its segment's full area.
final class ToolbarSegments: NSSegmentedControl, NSViewToolTipOwner {
    private let toolTips: [String]
    private var symbols: [String]

    init(symbols: [String], toolTips: [String], trackingMode: NSSegmentedControl.SwitchTracking) {
        self.toolTips = toolTips
        self.symbols = symbols
        super.init(frame: .zero)
        segmentCount = symbols.count
        self.trackingMode = trackingMode
        segmentDistribution = .fillEqually
        for (segment, symbol) in symbols.enumerated() {
            setImage(NSImage(systemSymbolName: symbol, accessibilityDescription: toolTips[segment]), forSegment: segment)
        }
    }

    func setSymbol(_ symbol: String, forSegment segment: Int) {
        guard symbols[segment] != symbol else { return }
        symbols[segment] = symbol
        setImage(NSImage(systemSymbolName: symbol, accessibilityDescription: toolTips[segment]), forSegment: segment)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        removeAllToolTips()
        let width = bounds.width / CGFloat(segmentCount)
        for segment in 0..<segmentCount {
            let rect = CGRect(x: bounds.minX + CGFloat(segment) * width, y: bounds.minY, width: width, height: bounds.height)
            addToolTip(rect, owner: self, userData: nil)
        }
    }

    func view(_ view: NSView, stringForToolTip tag: NSView.ToolTipTag, point: NSPoint, userData: UnsafeMutableRawPointer?) -> String {
        let width = bounds.width / CGFloat(segmentCount)
        let segment = Int((point.x - bounds.minX) / width)
        return toolTips[max(0, min(segment, toolTips.count - 1))]
    }
}

extension NSOpenPanel {
    static func forImages() -> NSOpenPanel {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.allowedContentTypes = [.image, .folder]
        panel.prompt = "Open"
        return panel
    }
}
