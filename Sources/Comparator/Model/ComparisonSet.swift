import AppKit

enum ViewMode {
    case single, split, difference
}

/// How split view divides the canvas: a vertical divider with images side by side, or a
/// horizontal one with images stacked. The lower-numbered image goes on the left or top.
enum SplitLayout {
    case sideBySide, stacked
}

enum AlignOverlay {
    case difference, onion
}

/// The images in one window, which one is shown, and how they're compared.
///
/// Images live in a shared world space: the reference image (the first loaded one) spans
/// x = 0...1, and every other image is scaled to the same width and centered on it. The
/// canvas camera looks at this space, so switching images never moves the view.
@MainActor
final class ComparisonSet {
    struct Change: OptionSet {
        let rawValue: Int
        /// Images added, removed or reordered.
        static let items = Change(rawValue: 1 << 0)
        /// An image finished loading (or failed to).
        static let content = Change(rawValue: 1 << 1)
        /// The current or other image changed.
        static let selection = Change(rawValue: 1 << 2)
        /// Mode, split layout, order or position, gain, pixel filter or align overlay changed.
        static let display = Change(rawValue: 1 << 3)
        /// An image's offset or scale changed.
        static let alignment = Change(rawValue: 1 << 4)
        /// An image was reloaded after changing on disk; see `lastReloaded`.
        static let reload = Change(rawValue: 1 << 5)
        /// A noise view image finished computing.
        static let noise = Change(rawValue: 1 << 6)
    }

    static let gains: [CGFloat] = [1, 2, 4, 8, 16, 32, 64]
    static let noiseGains: [CGFloat] = [5, 10, 15, 25, 40, 60, 100]
    static let noiseRadii: [CGFloat] = [1, 2, 3, 4, 6, 8, 12, 16, 24, 32, 48, 64]

    private(set) var items: [ImageItem] = []
    /// The image being shown.
    private(set) var currentID: UUID?
    /// The previously shown image: what Tab flips to, and the second image in split and difference views.
    private(set) var otherID: UUID?
    private(set) var lastReloaded: ImageItem?

    var mode: ViewMode = .single {
        didSet { if mode != oldValue { notify(.display) } }
    }
    var splitLayout: SplitLayout = .sideBySide {
        didSet { if splitLayout != oldValue { notify(.display) } }
    }
    /// Puts the higher-numbered image on the left or top in split mode.
    var splitSwapped = false {
        didSet { notify(.display) }
    }
    /// Divider position in split mode, as a fraction of the canvas width from the left, or
    /// of its height from the top when stacked.
    var splitPosition: CGFloat = 0.5 {
        didSet { notify(.display) }
    }
    var gainIndex = 0 {
        didSet { notify(.display) }
    }
    var pixelated = UserDefaults.standard.object(forKey: "pixelated") as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(pixelated, forKey: "pixelated")
            notify(.display)
        }
    }
    var alignOverlay: AlignOverlay = UserDefaults.standard.string(forKey: "alignOverlay") == "difference" ? .difference : .onion {
        didSet {
            UserDefaults.standard.set(alignOverlay == .onion ? "onion" : "difference", forKey: "alignOverlay")
            notify(.display)
        }
    }

    /// Shows every image as its noise view (see `NoiseFilter`).
    var noiseView = false {
        didSet {
            notify(.display)
            scheduleNoiseUpdate()
        }
    }
    var noiseGainIndex = UserDefaults.standard.object(forKey: "noiseGainIndex") as? Int ?? 3 {
        didSet {
            UserDefaults.standard.set(noiseGainIndex, forKey: "noiseGainIndex")
            notify(.display)
            scheduleNoiseUpdate()
        }
    }
    var noiseRadiusIndex = UserDefaults.standard.object(forKey: "noiseRadiusIndex") as? Int ?? 6 {
        didSet {
            UserDefaults.standard.set(noiseRadiusIndex, forKey: "noiseRadiusIndex")
            notify(.display)
            scheduleNoiseUpdate()
        }
    }

    private var observers: [@MainActor (Change) -> Void] = []
    private lazy var watcher = FileWatcher { [weak self] in self?.filesChanged() }

    var current: ImageItem? { items.first { $0.id == currentID } }
    var other: ImageItem? { items.first { $0.id == otherID } }
    var gain: CGFloat { Self.gains[gainIndex] }

    /// The current and other images in split view order: left to right, or top to bottom.
    var splitPair: (first: ImageItem, second: ImageItem)? {
        guard let current, let other else { return nil }
        let currentFirst = ((index(of: current) ?? 0) < (index(of: other) ?? 0)) != splitSwapped
        return currentFirst ? (current, other) : (other, current)
    }
    var noiseGain: CGFloat { Self.noiseGains[min(noiseGainIndex, Self.noiseGains.count - 1)] }
    /// Blur radius in pixels of the reference image.
    var noiseRadius: CGFloat { Self.noiseRadii[min(noiseRadiusIndex, Self.noiseRadii.count - 1)] }

    func index(of item: ImageItem) -> Int? {
        items.firstIndex { $0 === item }
    }

    func observe(_ handler: @escaping @MainActor (Change) -> Void) {
        observers.append(handler)
    }

    private func notify(_ change: Change) {
        if !change.isDisjoint(with: [.items, .content]) { scheduleNoiseUpdate() }
        for observer in observers { observer(change) }
    }

    func close() {
        watcher.stop()
    }

    // MARK: - Items

    /// Adds images (skipping ones already in the set) and shows the first new one.
    func add(_ urls: [URL], at index: Int? = nil) {
        let existing = Set(items.map(\.url.standardizedFileURL))
        let newItems = urls
            .filter { !existing.contains($0.standardizedFileURL) }
            .map(ImageItem.init)
        guard let first = newItems.first else { return }

        let wasEmpty = items.isEmpty
        items.insert(contentsOf: newItems, at: min(index ?? items.count, items.count))
        if wasEmpty {
            currentID = first.id
            otherID = newItems.dropFirst().first?.id
        } else {
            otherID = currentID
            currentID = first.id
        }

        newItems.forEach { load($0) }
        updateWatcher()
        notify([.items, .selection])
    }

    func remove(_ item: ImageItem) {
        guard let index = index(of: item) else { return }
        items.remove(at: index)
        if item.id == currentID {
            currentID = otherID ?? items[safe: min(index, items.count - 1)]?.id
            otherID = nil
        }
        repairSelection(near: index)
        updateWatcher()
        notify([.items, .selection])
    }

    func move(_ item: ImageItem, to destination: Int) {
        guard let source = index(of: item) else { return }
        items.remove(at: source)
        items.insert(item, at: min(destination > source ? destination - 1 : destination, items.count))
        notify(.items)
    }

    /// Keeps `current` valid and `other` distinct from it whenever there are two or more images.
    private func repairSelection(near index: Int = 0) {
        if current == nil { currentID = items.first?.id }
        if other == nil || otherID == currentID {
            let candidates = items.enumerated().filter { $0.element.id != currentID }
            let nearest = candidates.min { abs($0.offset - index) < abs($1.offset - index) }
            otherID = nearest?.element.id
        }
    }

    // MARK: - Selection

    func select(_ item: ImageItem) {
        guard item.id != currentID, index(of: item) != nil else { return }
        otherID = currentID
        currentID = item.id
        notify(.selection)
    }

    func select(index: Int) {
        guard let item = items[safe: index] else { return }
        select(item)
    }

    func flip() {
        guard let other else { return }
        select(other)
    }

    func step(_ delta: Int) {
        guard let current, let index = index(of: current), items.count > 1 else { return }
        select(index: (index + delta + items.count) % items.count)
    }

    func changeGain(by delta: Int) {
        let index = max(0, min(Self.gains.count - 1, gainIndex + delta))
        if index != gainIndex { gainIndex = index }
    }

    func changeNoiseGain(by delta: Int) {
        let index = max(0, min(Self.noiseGains.count - 1, noiseGainIndex + delta))
        if index != noiseGainIndex { noiseGainIndex = index }
    }

    func changeNoiseRadius(by delta: Int) {
        let index = max(0, min(Self.noiseRadii.count - 1, noiseRadiusIndex + delta))
        if index != noiseRadiusIndex { noiseRadiusIndex = index }
    }

    // MARK: - Geometry

    /// The first loaded image; it defines the world frame.
    var reference: ImageItem? { items.first { $0.isLoaded } }

    /// World units per image pixel for `item`.
    func worldPerPixel(_ item: ImageItem) -> CGFloat {
        guard item.pixelSize.width > 0 else { return 0 }
        return item.scale / item.pixelSize.width
    }

    func worldRect(for item: ImageItem) -> CGRect? {
        guard item.isLoaded, let reference else { return nil }
        let frameHeight = reference.pixelSize.height / reference.pixelSize.width
        let width = item.scale
        let height = item.scale * item.pixelSize.height / item.pixelSize.width
        let center = CGPoint(x: 0.5 + item.offset.x, y: frameHeight / 2 + item.offset.y)
        return CGRect(x: center.x - width / 2, y: center.y - height / 2, width: width, height: height)
    }

    /// The union of all loaded images.
    var contentBounds: CGRect? {
        items.compactMap(worldRect(for:)).reduce(nil) { $0?.union($1) ?? $1 }
    }

    /// Pixels per world unit of the highest-resolution image; "100%" zoom is relative to it.
    var maxPixelDensity: CGFloat {
        items.filter(\.isLoaded).map { $0.pixelSize.width / $0.scale }.max() ?? 1000
    }

    // MARK: - Alignment

    func moveImage(_ item: ImageItem, by delta: CGPoint) {
        item.offset.x += delta.x
        item.offset.y += delta.y
        notify(.alignment)
    }

    func nudge(_ item: ImageItem, pixels: CGPoint) {
        let unit = worldPerPixel(item)
        moveImage(item, by: CGPoint(x: pixels.x * unit, y: pixels.y * unit))
    }

    /// Scales `item` while keeping the image point under `anchor` (in world space) fixed.
    func scaleImage(_ item: ImageItem, by factor: CGFloat, around anchor: CGPoint) {
        guard let rect = worldRect(for: item) else { return }
        let newScale = max(0.01, min(100, item.scale * factor))
        let ratio = newScale / item.scale
        let newCenter = CGPoint(
            x: anchor.x + (rect.midX - anchor.x) * ratio,
            y: anchor.y + (rect.midY - anchor.y) * ratio
        )
        item.offset.x += newCenter.x - rect.midX
        item.offset.y += newCenter.y - rect.midY
        item.scale = newScale
        notify(.alignment)
    }

    func resetAlignment(_ item: ImageItem) {
        guard item.isAdjusted else { return }
        item.offset = .zero
        item.scale = 1
        notify(.alignment)
    }

    // MARK: - Noise view

    /// What the canvas draws for `item`: the image itself, or its noise view when that's on.
    /// While a noise view is being computed, the previous one (or the image) is shown.
    func displayImage(for item: ImageItem) -> CGImage? {
        guard noiseView else { return item.image }
        return item.noise?.image ?? item.image
    }

    var isComputingNoise: Bool {
        noiseView && items.contains { $0.pendingNoiseKey != nil }
    }

    /// The radius is measured in reference-image pixels, so an upscaled image gets a
    /// proportionally larger blur and both cover the same area of the picture.
    private func noiseKey(for item: ImageItem) -> NoiseKey? {
        guard let image = item.image, let reference else { return nil }
        let sigma = noiseRadius * item.pixelSize.width / reference.pixelSize.width
        return NoiseKey(sigma: sigma, gain: noiseGain, source: ObjectIdentifier(image))
    }

    private var noiseUpdate: Task<Void, Never>?

    /// Coalesces rapid setting changes (e.g. holding a key) into one recompute.
    private func scheduleNoiseUpdate() {
        guard noiseView else { return }
        noiseUpdate?.cancel()
        noiseUpdate = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(100))
            guard !Task.isCancelled else { return }
            self?.updateNoise()
        }
    }

    private func updateNoise() {
        guard noiseView else { return }
        // Start with the images on screen.
        var seen = Set<UUID>()
        let ordered = ([current, other].compactMap { $0 } + items).filter { seen.insert($0.id).inserted }

        for item in ordered {
            guard let image = item.image, let key = noiseKey(for: item),
                  item.noise?.key != key, item.pendingNoiseKey != key, item.failedNoiseKey != key
            else { continue }
            item.pendingNoiseKey = key
            let source = SendableImage(image: image)

            Task { [weak self] in
                let result = await Task.detached(priority: .userInitiated) {
                    NoiseFilter.render(source.image, sigma: key.sigma, gain: key.gain).map(SendableImage.init)
                }.value
                guard let self, item.pendingNoiseKey == key else { return }
                item.pendingNoiseKey = nil
                if let result {
                    item.noise = (key, result.image)
                } else {
                    item.failedNoiseKey = key
                }
                self.notify(.noise)
            }
        }
    }

    // MARK: - Loading

    private func load(_ item: ImageItem, isReload: Bool = false) {
        item.generation += 1
        let generation = item.generation
        let url = item.url

        Task { [weak self] in
            let result = await Task.detached(priority: .userInitiated) {
                Result { try ImageDecoder.decode(url) }
            }.value
            guard let self, item.generation == generation, self.index(of: item) != nil else { return }

            switch result {
            case .success(let decoded):
                item.image = decoded.image
                item.pixelSize = CGSize(width: decoded.image.width, height: decoded.image.height)
                item.thumbnail = decoded.thumbnail.map {
                    NSImage(cgImage: $0, size: NSSize(width: $0.width, height: $0.height))
                }
                item.stamp = decoded.stamp
                item.info = decoded.info
                item.error = nil
                item.failedReloads = 0
                if isReload {
                    self.lastReloaded = item
                    self.notify([.content, .reload])
                } else {
                    self.notify(.content)
                }
                // The file may have been written again while it was decoding.
                if FileStamp.of(url) != decoded.stamp {
                    self.load(item, isReload: true)
                }

            case .failure(let error):
                if isReload, item.isLoaded {
                    // Likely caught mid-write; try again shortly and keep showing the previous version.
                    item.failedReloads += 1
                    guard item.failedReloads <= 3 else { return }
                    try? await Task.sleep(for: .milliseconds(400))
                    if item.generation == generation { self.load(item, isReload: true) }
                } else {
                    item.error = error.localizedDescription
                    self.notify(.content)
                }
            }
        }
    }

    private func updateWatcher() {
        let directories = Set(items.map { $0.url.resolvingSymlinksInPath().deletingLastPathComponent().path })
        watcher.watch(directories)
    }

    private func filesChanged() {
        for item in items {
            guard let stamp = FileStamp.of(item.url), stamp != item.stamp else { continue }
            item.stamp = stamp
            load(item, isReload: item.isLoaded)
        }
    }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
