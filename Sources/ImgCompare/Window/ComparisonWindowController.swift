import AppKit

/// A window (or tab) showing one comparison set: the image list on the left, the canvas on the right.
final class ComparisonWindowController: NSWindowController, NSWindowDelegate, NSToolbarDelegate {
    let imageSet = ComparisonSet()
    let canvas: CanvasView
    var onClose: (() -> Void)?

    private let modeControl = NSSegmentedControl(
        labels: ["Single", "Split", "Difference"],
        trackingMode: .selectOne,
        target: nil,
        action: nil
    )
    private let noiseControl = NSSegmentedControl(
        labels: ["Noise"],
        trackingMode: .selectAny,
        target: nil,
        action: nil
    )
    private let filterControl = NSSegmentedControl(
        labels: ["Pixels", "Smooth"],
        trackingMode: .selectOne,
        target: nil,
        action: nil
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
        filterControl.target = self
        noiseControl.target = self
        noiseControl.action = #selector(noiseChanged(_:))
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
        modeControl.selectedSegment = switch imageSet.mode {
        case .single: 0
        case .split: 1
        case .difference: 2
        }
        filterControl.selectedSegment = imageSet.pixelated ? 0 : 1
        noiseControl.setSelected(imageSet.noiseView, forSegment: 0)
    }

    @objc private func modeChanged(_ sender: NSSegmentedControl) {
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
        imageSet.pixelated = sender.selectedSegment == 0
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
        [.toggleSidebar, .sidebarTrackingSeparator, .flexibleSpace, Self.modeItem, Self.noiseItem, Self.filterItem]
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
            item.toolTip = "Split (S), Difference (D)"
        case Self.noiseItem:
            item.view = noiseControl
            item.label = "Noise"
            item.toolTip = "Noise view (N): flat areas gray, faint color patches as colored blobs"
        case Self.filterItem:
            item.view = filterControl
            item.label = "Filtering"
            item.toolTip = "Pixels or smooth filtering when zoomed in (P)"
        default:
            return nil
        }
        return item
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
