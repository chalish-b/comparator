import AppKit

/// Lists the images in a set. Click to show one, drag to reorder, drop files to add.
final class SidebarViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate, NSMenuDelegate {
    private static let rowType = NSPasteboard.PasteboardType("dev.chalish.comparator.item")

    let imageSet: ComparisonSet
    private let tableView = NSTableView()
    private var isSyncingSelection = false

    init(set: ComparisonSet) {
        self.imageSet = set
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

        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 300, height: 600))
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        view = scrollView

        imageSet.observe { [weak self] change in self?.setDidChange(change) }
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        tableView.sizeLastColumnToFit()
    }

    private func setDidChange(_ change: ComparisonSet.Change) {
        if change.contains(.items) {
            tableView.reloadData()
        } else if !change.isDisjoint(with: [.content, .selection, .display, .alignment]) {
            let rows = IndexSet(integersIn: 0..<imageSet.items.count)
            tableView.reloadData(forRowIndexes: rows, columnIndexes: [0])
        }
        syncSelection()
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

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard !isSyncingSelection, let item = imageSet.items[safe: tableView.selectedRow] else { return }
        imageSet.select(item)
    }

    /// "L"/"R" or "U"/"D" for the two sides of a split, otherwise a Tab marker on the image Tab flips to.
    private func badge(for item: ImageItem) -> String? {
        guard let current = imageSet.current, let other = imageSet.other, item === current || item === other else { return nil }
        if imageSet.mode == .split {
            let currentFirst = (imageSet.index(of: current) ?? 0) < (imageSet.index(of: other) ?? 0)
            let (first, second) = imageSet.splitLayout == .sideBySide ? ("L", "R") : ("U", "D")
            return (item === current) == currentFirst ? first : second
        }
        return item === other ? "⇥" : nil
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

    private static func format(ratio: CGFloat) -> String {
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
