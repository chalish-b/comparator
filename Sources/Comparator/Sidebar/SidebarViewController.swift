import AppKit

/// Lists the images in a set. Click to show one, drag to reorder, drop files to add. Below the
/// list, a resizable Info section describes the images shown.
final class SidebarViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate, NSMenuDelegate {
    private static let rowType = NSPasteboard.PasteboardType("dev.chalish.comparator.item")

    let imageSet: ComparisonSet
    private let tableView = NSTableView()
    private var isSyncingSelection = false
    private let infoPanel: InfoPanelView
    private var splitView: SidebarSplitView!

    /// Whether the Info section shows its contents, and its height when it does. Shared by all windows.
    private(set) var isInfoExpanded = UserDefaults.standard.object(forKey: "infoExpanded") as? Bool ?? true {
        didSet { UserDefaults.standard.set(isInfoExpanded, forKey: "infoExpanded") }
    }
    private var infoHeight = UserDefaults.standard.object(forKey: "infoHeight") as? CGFloat ?? 250 {
        didSet { UserDefaults.standard.set(infoHeight, forKey: "infoHeight") }
    }

    init(set: ComparisonSet) {
        self.imageSet = set
        infoPanel = InfoPanelView(set: set)
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("image"))
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.style = .sourceList
        tableView.rowHeight = 56
        tableView.backgroundColor = .clear
        // Keyboard input stays with the canvas so shortcuts always work.
        tableView.refusesFirstResponder = true
        tableView.dataSource = self
        tableView.delegate = self
        tableView.registerForDraggedTypes([Self.rowType, .fileURL])
        tableView.setDraggingSourceOperationMask(.move, forLocal: true)

        let menu = NSMenu()
        menu.delegate = self
        tableView.menu = menu

        let scrollView = NSScrollView()
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false

        infoPanel.isExpanded = isInfoExpanded
        infoPanel.onToggle = { [weak self] in self?.toggleInfo() }

        splitView = SidebarSplitView(
            top: scrollView,
            bottom: infoPanel,
            bottomHeight: isInfoExpanded ? infoHeight : InfoPanelView.headerHeight,
            minimumBottomHeight: InfoPanelView.headerHeight
        )
        splitView.onDrag = { [weak self] height in self?.dividerDragged(to: height) }
        infoPanel.onHeaderDragStart = { [weak self] event in self?.splitView.beginDividerDrag(with: event) }
        infoPanel.onHeaderDrag = { [weak self] event in self?.splitView.continueDividerDrag(with: event) }
        view = splitView

        imageSet.observe { [weak self] change in self?.setDidChange(change) }
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        tableView.sizeLastColumnToFit()
    }

    // MARK: - Info section

    func toggleInfo() {
        setInfoExpanded(!isInfoExpanded)
    }

    func setInfoExpanded(_ expanded: Bool) {
        isInfoExpanded = expanded
        infoPanel.isExpanded = expanded
        splitView.bottomHeight = expanded ? infoHeight : InfoPanelView.headerHeight
    }

    /// Dragging the divider down to the header collapses the section; dragging it up expands it.
    private func dividerDragged(to height: CGFloat) {
        let height = min(height, splitView.maximumBottomHeight)
        let expanded = height > InfoPanelView.headerHeight + 8
        if expanded { infoHeight = height }
        if expanded != isInfoExpanded {
            isInfoExpanded = expanded
            infoPanel.isExpanded = expanded
        }
        splitView.bottomHeight = expanded ? height : InfoPanelView.headerHeight
    }

    private func setDidChange(_ change: ComparisonSet.Change) {
        if change.contains(.items) {
            tableView.reloadData()
        } else if !change.isDisjoint(with: [.content, .selection, .display, .alignment]) {
            let rows = IndexSet(integersIn: 0..<imageSet.items.count)
            tableView.reloadData(forRowIndexes: rows, columnIndexes: [0])
        }
        syncSelection()
        tableView.enumerateAvailableRowViews { rowView, row in
            (rowView as? ImageTableRowView)?.isShown = isShownUnselected(row: row)
        }
    }

    private func syncSelection() {
        isSyncingSelection = true
        defer { isSyncingSelection = false }
        if let current = imageSet.current, let row = imageSet.index(of: current) {
            tableView.selectRowIndexes([row], byExtendingSelection: false)
            tableView.scrollRowToVisible(row)
        } else {
            tableView.deselectAll(nil)
        }
    }

    /// Whether `row` is the second image on the canvas in split and difference views.
    private func isShownUnselected(row: Int) -> Bool {
        guard imageSet.mode != .single, let other = imageSet.other else { return false }
        return imageSet.index(of: other) == row
    }

    // MARK: - Rows

    func numberOfRows(in tableView: NSTableView) -> Int {
        imageSet.items.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let cell = tableView.makeView(withIdentifier: ImageRowView.identifier, owner: nil) as? ImageRowView ?? ImageRowView()
        let item = imageSet.items[row]
        cell.configure(index: row, item: item, detail: detail(for: item), badge: badge(for: item))
        return cell
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        let rowView = ImageTableRowView()
        rowView.isShown = isShownUnselected(row: row)
        return rowView
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard !isSyncingSelection, let item = imageSet.items[safe: tableView.selectedRow] else { return }
        imageSet.select(item)
    }

    /// Which half each image of a split is in, otherwise a Tab marker on the image Tab flips to.
    private func badge(for item: ImageItem) -> ImageRowView.Badge? {
        guard let current = imageSet.current, let other = imageSet.other, item === current || item === other else { return nil }
        if imageSet.mode == .split, let pair = imageSet.splitPair {
            let (first, second) = imageSet.splitLayout == .sideBySide
                ? ("rectangle.lefthalf.filled", "rectangle.righthalf.filled")
                : ("rectangle.tophalf.filled", "rectangle.bottomhalf.filled")
            return .symbol(item === pair.first ? first : second)
        }
        return item === other ? .key("⇥") : nil
    }

    private func detail(for item: ImageItem) -> String {
        guard item.isLoaded else { return item.error != nil ? "Couldn't open" : "Loading…" }
        let width = item.pixelSize.width, height = item.pixelSize.height
        var parts = ["\(Int(width))×\(Int(height))"]
        if let reference = imageSet.reference, reference !== item {
            let ratio = width / reference.pixelSize.width
            if abs(ratio - 1) > 0.001 { parts.append(Self.format(ratio: ratio)) }
            let aspect = height / width
            let referenceAspect = reference.pixelSize.height / reference.pixelSize.width
            if abs(aspect / referenceAspect - 1) > 0.002 { parts.append("different aspect") }
        }
        if item.isAdjusted { parts.append("aligned") }
        return parts.joined(separator: " · ")
    }

    static func format(ratio: CGFloat) -> String {
        let rounded = (ratio * 100).rounded() / 100
        let text = rounded == rounded.rounded() ? String(Int(rounded)) : String(format: "%g", rounded)
        return "\(text)×"
    }

    // MARK: - Drag and drop

    func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> (any NSPasteboardWriting)? {
        let item = NSPasteboardItem()
        item.setString(imageSet.items[row].id.uuidString, forType: Self.rowType)
        return item
    }

    func tableView(
        _ tableView: NSTableView,
        validateDrop info: any NSDraggingInfo,
        proposedRow row: Int,
        proposedDropOperation dropOperation: NSTableView.DropOperation
    ) -> NSDragOperation {
        tableView.setDropRow(row, dropOperation: .above)
        if info.draggingSource as? NSTableView === tableView { return .move }
        return droppedImages(info).isEmpty ? [] : .copy
    }

    func tableView(
        _ tableView: NSTableView,
        acceptDrop info: any NSDraggingInfo,
        row: Int,
        dropOperation: NSTableView.DropOperation
    ) -> Bool {
        if let idString = info.draggingPasteboard.string(forType: Self.rowType) {
            guard let item = imageSet.items.first(where: { $0.id.uuidString == idString }) else { return false }
            imageSet.move(item, to: row)
            return true
        }
        let urls = droppedImages(info)
        guard !urls.isEmpty else { return false }
        imageSet.add(urls, at: row)
        return true
    }

    private func droppedImages(_ info: any NSDraggingInfo) -> [URL] {
        let urls = info.draggingPasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL] ?? []
        return ImageFiles.expand(urls)
    }

    // MARK: - Context menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        guard let item = imageSet.items[safe: tableView.clickedRow] else { return }

        let reveal = NSMenuItem(title: "Show in Finder", action: #selector(showInFinder(_:)), keyEquivalent: "")
        let reset = NSMenuItem(title: "Reset Alignment", action: #selector(resetAlignment(_:)), keyEquivalent: "")
        let remove = NSMenuItem(title: "Remove from Set", action: #selector(remove(_:)), keyEquivalent: "")
        reset.isEnabled = item.isAdjusted
        for menuItem in [reveal, reset, remove] {
            menuItem.target = self
            menuItem.representedObject = item.id
        }
        menu.autoenablesItems = false
        menu.addItem(reveal)
        menu.addItem(reset)
        menu.addItem(.separator())
        menu.addItem(remove)
    }

    private func item(for sender: Any?) -> ImageItem? {
        guard let id = (sender as? NSMenuItem)?.representedObject as? UUID else { return nil }
        return imageSet.items.first { $0.id == id }
    }

    @objc private func showInFinder(_ sender: Any?) {
        if let item = item(for: sender) { NSWorkspace.shared.activateFileViewerSelecting([item.url]) }
    }

    @objc private func resetAlignment(_ sender: Any?) {
        if let item = item(for: sender) { imageSet.resetAlignment(item) }
    }

    @objc private func remove(_ sender: Any?) {
        if let item = item(for: sender) { imageSet.remove(item) }
    }
}
