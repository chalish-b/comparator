import AppKit
import CoreImage
import QuartzCore

/// Draws a comparison set and handles zoom, pan, image switching and alignment.
///
/// The camera (`zoom` in points per world unit, and the world point at the view's center)
/// is shared by every image in the set.
final class CanvasView: NSView, NSMenuItemValidation {
    private enum Drag {
        case pan(last: CGPoint)
        case divider
        case align(last: CGPoint)
    }

    private enum Composite {
        case empty
        case single(ImageItem)
        case split(left: ImageItem, right: ImageItem)
        case difference(top: ImageItem, bottom: ImageItem?, gain: CGFloat)
        case onion(top: ImageItem, bottom: ImageItem?)
    }

    let imageSet: ComparisonSet

    private let host = LayerHostView()
    private let group = CALayer()
    private let leftClip = CALayer()
    private let rightClip = CALayer()
    private let divider = CALayer()
    private let knob = CALayer()
    private var imageLayers: [UUID: CALayer] = [:]

    private var zoom: CGFloat = 1000
    private var center = CGPoint(x: 0.5, y: 0.5)
    private var isFitted = true
    private var hadContent = false
    private var optionHeld = false
    private var drag: Drag?

    private let flashLabel = HUDLabel(fontSize: 12, weight: .medium)
    private let centerTag = HUDLabel(fontSize: 13, weight: .semibold)
    private let statusLabel = HUDLabel(fontSize: 11)
    private let leftTag = HUDLabel(fontSize: 12, weight: .medium)
    private let rightTag = HUDLabel(fontSize: 12, weight: .medium)
    private let messageLabel = HUDLabel(fontSize: 14, weight: .medium)
    private let helpLabel = HUDLabel(fontSize: 12, monospaced: true)
    private var flashTask: Task<Void, Never>?

    private static let background = NSColor(white: 0.11, alpha: 1).cgColor

    init(set: ComparisonSet) {
        self.imageSet = set
        super.init(frame: NSRect(x: 0, y: 0, width: 900, height: 600))
        wantsLayer = true

        host.frame = bounds
        host.autoresizingMask = [.width, .height]
        addSubview(host)

        setUpLayers()
        setUpHUD()
        registerForDraggedTypes([.fileURL])

        imageSet.observe { [weak self] change in self?.setDidChange(change) }
        render()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    private func setUpLayers() {
        let root = host.root
        root.backgroundColor = Self.background
        for clip in [leftClip, rightClip] {
            clip.masksToBounds = true
            clip.anchorPoint = .zero
        }
        group.anchorPoint = .zero
        divider.backgroundColor = NSColor.white.cgColor
        divider.shadowOpacity = 0.6
        divider.shadowRadius = 2
        divider.shadowOffset = .zero
        knob.backgroundColor = NSColor.white.cgColor
        knob.cornerRadius = 7
        knob.shadowOpacity = 0.5
        knob.shadowRadius = 3
        knob.shadowOffset = .zero
        root.addSublayer(group)
        root.addSublayer(leftClip)
        root.addSublayer(rightClip)
        root.addSublayer(divider)
        root.addSublayer(knob)
        for layer in [group, leftClip, rightClip, divider, knob] {
            layer.actions = Self.noActions
        }
    }

    private func setUpHUD() {
        for label in [flashLabel, centerTag, statusLabel, leftTag, rightTag, messageLabel, helpLabel] {
            addSubview(label)
        }
        statusLabel.alphaValue = 0.85
        helpLabel.text = Self.helpText
        helpLabel.isHidden = true

        let safe = safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            centerTag.centerXAnchor.constraint(equalTo: safe.centerXAnchor),
            centerTag.topAnchor.constraint(equalTo: safe.topAnchor, constant: 12),
            centerTag.widthAnchor.constraint(lessThanOrEqualTo: safe.widthAnchor, multiplier: 0.6),

            flashLabel.centerXAnchor.constraint(equalTo: safe.centerXAnchor),
            flashLabel.topAnchor.constraint(equalTo: safe.topAnchor, constant: 48),
            flashLabel.widthAnchor.constraint(lessThanOrEqualTo: safe.widthAnchor, multiplier: 0.5),

            statusLabel.leadingAnchor.constraint(equalTo: safe.leadingAnchor, constant: 12),
            statusLabel.bottomAnchor.constraint(equalTo: safe.bottomAnchor, constant: -12),
            statusLabel.trailingAnchor.constraint(lessThanOrEqualTo: safe.trailingAnchor, constant: -12),

            leftTag.leadingAnchor.constraint(equalTo: safe.leadingAnchor, constant: 12),
            leftTag.topAnchor.constraint(equalTo: safe.topAnchor, constant: 12),
            leftTag.widthAnchor.constraint(lessThanOrEqualTo: safe.widthAnchor, multiplier: 0.3),

            rightTag.trailingAnchor.constraint(equalTo: safe.trailingAnchor, constant: -12),
            rightTag.topAnchor.constraint(equalTo: safe.topAnchor, constant: 12),
            rightTag.widthAnchor.constraint(lessThanOrEqualTo: safe.widthAnchor, multiplier: 0.3),

            messageLabel.centerXAnchor.constraint(equalTo: safe.centerXAnchor),
            messageLabel.centerYAnchor.constraint(equalTo: safe.centerYAnchor),
            messageLabel.widthAnchor.constraint(lessThanOrEqualTo: safe.widthAnchor, multiplier: 0.8),

            helpLabel.centerXAnchor.constraint(equalTo: safe.centerXAnchor),
            helpLabel.centerYAnchor.constraint(equalTo: safe.centerYAnchor),
        ])
    }

    private static let noActions: [String: any CAAction] = [
        "position": NSNull(), "bounds": NSNull(), "frame": NSNull(), "contents": NSNull(),
        "opacity": NSNull(), "hidden": NSNull(), "sublayers": NSNull(), "filters": NSNull(),
        "compositingFilter": NSNull(), "backgroundColor": NSNull(),
        "magnificationFilter": NSNull(), "minificationFilter": NSNull(),
    ]

    // MARK: - Model changes

    private func setDidChange(_ change: ComparisonSet.Change) {
        let hasContent = imageSet.contentBounds != nil
        if hasContent, !hadContent || (isFitted && !change.isDisjoint(with: [.items, .content])) {
            fit()
        }
        hadContent = hasContent

        if change.contains(.reload), let item = imageSet.lastReloaded, item === imageSet.current || item === imageSet.other {
            flash("Reloaded \(item.name)")
        }
        render()
    }

    // MARK: - Coordinates

    private var backingScale: CGFloat { window?.backingScaleFactor ?? 2 }

    /// The zoom at which one pixel of the highest-resolution image covers one device pixel.
    private var actualPixelsZoom: CGFloat { imageSet.maxPixelDensity / backingScale }

    private var zoomPercent: CGFloat { zoom / actualPixelsZoom * 100 }

    private func viewPoint(_ world: CGPoint) -> CGPoint {
        CGPoint(
            x: bounds.midX + (world.x - center.x) * zoom,
            y: bounds.midY - (world.y - center.y) * zoom
        )
    }

    private func worldPoint(_ view: CGPoint) -> CGPoint {
        CGPoint(
            x: center.x + (view.x - bounds.midX) / zoom,
            y: center.y - (view.y - bounds.midY) / zoom
        )
    }

    /// World rects have a top-left origin; view rects have a bottom-left origin.
    private func viewRect(_ world: CGRect) -> CGRect {
        let topLeft = viewPoint(world.origin)
        return CGRect(
            x: topLeft.x,
            y: topLeft.y - world.height * zoom,
            width: world.width * zoom,
            height: world.height * zoom
        )
    }

    private var dividerX: CGFloat { (bounds.width * imageSet.splitPosition).rounded() }

    // MARK: - Camera

    private func clampedZoom(_ value: CGFloat) -> CGFloat {
        let content = imageSet.contentBounds ?? CGRect(x: 0, y: 0, width: 1, height: 1)
        let minimum = 24 / max(content.width, content.height)
        let maximum = actualPixelsZoom * 256
        return min(max(value, minimum), maximum)
    }

    private func fit() {
        guard let content = imageSet.contentBounds, bounds.width > 0, bounds.height > 0 else { return }
        let available = safeAreaRect.insetBy(dx: 16, dy: 16)
        guard available.width > 0, available.height > 0 else { return }
        zoom = min(available.width / content.width, available.height / content.height)
        center = CGPoint(
            x: content.midX - (available.midX - bounds.midX) / zoom,
            y: content.midY + (available.midY - bounds.midY) / zoom
        )
        isFitted = true
    }

    private func setZoom(_ value: CGFloat, around point: CGPoint) {
        let anchor = worldPoint(point)
        zoom = clampedZoom(value)
        center = CGPoint(
            x: anchor.x - (point.x - bounds.midX) / zoom,
            y: anchor.y + (point.y - bounds.midY) / zoom
        )
        isFitted = false
        render()
    }

    private func pan(by delta: CGPoint) {
        center.x -= delta.x / zoom
        center.y += delta.y / zoom
        isFitted = false
        render()
    }

    /// Zooms to the next power-of-two percentage, so pixels stay evenly sized.
    private func zoomStep(_ direction: Int) {
        let level = log2(zoomPercent / 100)
        let next = direction > 0 ? floor(level + 0.001) + 1 : ceil(level - 0.001) - 1
        setZoom(actualPixelsZoom * pow(2, next), around: zoomAnchor)
    }

    /// The mouse location if it's over the canvas, otherwise the center of the visible area.
    private var zoomAnchor: CGPoint {
        if let window {
            let mouse = convert(window.mouseLocationOutsideOfEventStream, from: nil)
            if bounds.contains(mouse) { return mouse }
        }
        return CGPoint(x: safeAreaRect.midX, y: safeAreaRect.midY)
    }

    private func toggleFitOrActualPixels(at point: CGPoint) {
        if isFitted {
            setZoom(actualPixelsZoom, around: point)
        } else {
            fit()
            render()
        }
    }

    override func layout() {
        super.layout()
        if isFitted { fit() }
        render()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        render()
    }

    // MARK: - Rendering

    private var isAligning: Bool {
        if case .align = drag { return true }
        return optionHeld
    }

    private func composite() -> Composite {
        guard let current = imageSet.current, current.isLoaded else { return .empty }
        let other = imageSet.other.flatMap { $0.isLoaded ? $0 : nil }

        if isAligning {
            switch imageSet.alignOverlay {
            case .onion:
                return .onion(top: current, bottom: other)
            case .difference:
                return .difference(top: current, bottom: other, gain: imageSet.mode == .difference ? imageSet.gain : 1)
            }
        }

        guard let other else { return .single(current) }
        switch imageSet.mode {
        case .single:
            return .single(current)
        case .split:
            let currentFirst = (imageSet.index(of: current) ?? 0) < (imageSet.index(of: other) ?? 0)
            return currentFirst ? .split(left: current, right: other) : .split(left: other, right: current)
        case .difference:
            return .difference(top: current, bottom: other, gain: imageSet.gain)
        }
    }

    private func render() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        let scale = backingScale
        let root = host.root
        root.frame = bounds
        for layer in [root, group, leftClip, rightClip, divider, knob] {
            layer.contentsScale = scale
        }

        let liveIDs = Set(imageSet.items.map(\.id))
        for (id, layer) in imageLayers where !liveIDs.contains(id) {
            layer.removeFromSuperlayer()
            imageLayers[id] = nil
        }

        group.sublayers = nil
        leftClip.sublayers = nil
        rightClip.sublayers = nil
        group.filters = nil
        group.frame = bounds
        root.backgroundColor = Self.background
        var showsDivider = false

        let composite = composite()
        switch composite {
        case .empty:
            break

        case .single(let item):
            group.addSublayer(imageLayer(for: item, origin: .zero))

        case .split(let left, let right):
            let x = dividerX
            leftClip.frame = CGRect(x: 0, y: 0, width: x, height: bounds.height)
            rightClip.frame = CGRect(x: x, y: 0, width: bounds.width - x, height: bounds.height)
            leftClip.addSublayer(imageLayer(for: left, origin: .zero))
            rightClip.addSublayer(imageLayer(for: right, origin: CGPoint(x: x, y: 0)))
            divider.frame = CGRect(x: x - 0.5, y: 0, width: 1, height: bounds.height)
            knob.frame = CGRect(x: x - 7, y: bounds.midY - 7, width: 14, height: 14)
            showsDivider = true

        case .difference(let top, let bottom, let gain):
            root.backgroundColor = NSColor.black.cgColor
            if let bottom { group.addSublayer(imageLayer(for: bottom, origin: .zero)) }
            let topLayer = imageLayer(for: top, origin: .zero)
            topLayer.compositingFilter = CIFilter(name: "CIDifferenceBlendMode")
            group.addSublayer(topLayer)
            if gain > 1 { group.filters = [Self.gainFilter(gain)] }

        case .onion(let top, let bottom):
            if let bottom { group.addSublayer(imageLayer(for: bottom, origin: .zero)) }
            let topLayer = imageLayer(for: top, origin: .zero)
            topLayer.opacity = 0.5
            group.addSublayer(topLayer)
        }

        leftClip.isHidden = !showsDivider
        rightClip.isHidden = !showsDivider
        divider.isHidden = !showsDivider
        knob.isHidden = !showsDivider

        updateHUD(composite)
        window?.invalidateCursorRects(for: self)
    }

    /// The layer for `item`, positioned for a container whose origin is at `origin` in view space.
    private func imageLayer(for item: ImageItem, origin: CGPoint) -> CALayer {
        let layer: CALayer
        if let existing = imageLayers[item.id] {
            layer = existing
        } else {
            layer = CALayer()
            layer.actions = Self.noActions
            imageLayers[item.id] = layer
        }
        if let image = imageSet.displayImage(for: item), (layer.contents as AnyObject?) !== image {
            layer.contents = image
        }
        layer.magnificationFilter = imageSet.pixelated ? .nearest : .linear
        layer.minificationFilter = .trilinear
        layer.contentsScale = backingScale
        layer.compositingFilter = nil
        layer.opacity = 1
        if let rect = imageSet.worldRect(for: item) {
            layer.frame = viewRect(rect).offsetBy(dx: -origin.x, dy: -origin.y)
        }
        return layer
    }

    private static func gainFilter(_ gain: CGFloat) -> CIFilter {
        let filter = CIFilter(name: "CIColorMatrix")!
        filter.setValue(CIVector(x: gain, y: 0, z: 0, w: 0), forKey: "inputRVector")
        filter.setValue(CIVector(x: 0, y: gain, z: 0, w: 0), forKey: "inputGVector")
        filter.setValue(CIVector(x: 0, y: 0, z: gain, w: 0), forKey: "inputBVector")
        filter.setValue(CIVector(x: 0, y: 0, z: 0, w: 1), forKey: "inputAVector")
        return filter
    }

    // MARK: - HUD

    private func label(for item: ImageItem) -> String {
        let number = (imageSet.index(of: item) ?? 0) + 1
        return "\(number) · \(item.name)"
    }

    private func updateHUD(_ composite: Composite) {
        if imageSet.items.isEmpty {
            messageLabel.text = "Drop images here"
        } else if let current = imageSet.current, !current.isLoaded {
            messageLabel.text = current.error.map { "Couldn't open \(current.name)\n\($0)" } ?? "Loading \(current.name)…"
        } else {
            messageLabel.text = nil
        }

        leftTag.text = nil
        rightTag.text = nil
        centerTag.text = nil
        switch composite {
        case .empty:
            break
        case .single(let item):
            centerTag.text = label(for: item)
        case .split(let left, let right):
            leftTag.text = label(for: left)
            rightTag.text = label(for: right)
        case .difference(let top, let bottom, _):
            centerTag.text = bottom.map { "\(label(for: top)) − \(label(for: $0))" } ?? label(for: top)
        case .onion(let top, let bottom):
            centerTag.text = bottom.map { "\(label(for: top)) over \(label(for: $0))" } ?? label(for: top)
        }

        statusLabel.text = statusText(composite)
    }

    private func statusText(_ composite: Composite) -> String? {
        if case .empty = composite { return nil }
        var parts = [Self.format(percent: zoomPercent)]

        if isAligning, let current = imageSet.current {
            let unit = imageSet.worldPerPixel(current)
            let dx = unit > 0 ? current.offset.x / unit : 0
            let dy = unit > 0 ? current.offset.y / unit : 0
            parts.append("Aligning")
            parts.append(String(format: "offset %+.1f, %+.1f px", dx, dy))
            parts.append(String(format: "scale %.2f%%", current.scale * 100))
        } else if case .difference(_, _, let gain) = composite {
            parts.append("Difference ×\(Int(gain))")
        }
        if imageSet.noiseView {
            parts.append(noiseDescription + (imageSet.isComputingNoise ? " (updating…)" : ""))
        }
        return parts.joined(separator: "  ·  ")
    }

    private var noiseDescription: String {
        "Noise ×\(Int(imageSet.noiseGain)), radius \(Int(imageSet.noiseRadius)) px"
    }

    private static func format(percent: CGFloat) -> String {
        percent < 10 ? String(format: "%.1f%%", percent) : String(format: "%.0f%%", percent)
    }

    private func flash(_ text: String) {
        flashTask?.cancel()
        flashLabel.text = text
        flashLabel.alphaValue = 1
        flashTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(1100))
            guard !Task.isCancelled, let label = self?.flashLabel else { return }
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.3
                label.animator().alphaValue = 0
            }, completionHandler: nil)
        }
    }

    private static let helpText = """
        1–9          Show image
        Tab          Flip to last viewed image
        ← →          Previous / next image
        S            Split view
        D            Difference view
        N            Noise view
        ↑ ↓          Difference gain / noise strength
        , .          Noise radius
        P            Pixels / smooth
        0 or F       Fit
        A            Actual pixels (100%)
        + −          Zoom in / out
        Double-click Fit / 100%
        Drag         Pan

        Hold ⌥       Alignment overlay
        ⌥ drag       Move image
        ⌥ arrows     Nudge 1 px (⇧ for 10 px)
        ⌥ scroll     Scale image
        ⌥ R          Reset alignment
        O            Overlay: difference / onion skin

        ⌫            Remove image from set
        H            Show / hide this help
        """

    // MARK: - Mouse

    override var acceptsFirstResponder: Bool { true }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func resetCursorRects() {
        if case .split = composite() {
            addCursorRect(CGRect(x: dividerX - 5, y: 0, width: 10, height: bounds.height), cursor: .resizeLeftRight)
        }
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let point = convert(event.locationInWindow, from: nil)

        if event.clickCount == 2 {
            drag = nil
            toggleFitOrActualPixels(at: point)
            return
        }
        if event.modifierFlags.contains(.option), imageSet.current?.isLoaded == true {
            drag = .align(last: point)
            render()
            return
        }
        if case .split = composite(), abs(point.x - dividerX) <= 6 {
            drag = .divider
            return
        }
        drag = .pan(last: point)
        NSCursor.closedHand.push()
    }

    override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        switch drag {
        case .pan(let last):
            drag = .pan(last: point)
            pan(by: CGPoint(x: point.x - last.x, y: point.y - last.y))
        case .divider:
            imageSet.splitPosition = min(max(point.x / bounds.width, 0), 1)
        case .align(let last):
            drag = .align(last: point)
            if let current = imageSet.current {
                imageSet.moveImage(current, by: CGPoint(x: (point.x - last.x) / zoom, y: -(point.y - last.y) / zoom))
            }
        case nil:
            break
        }
    }

    override func mouseUp(with event: NSEvent) {
        if case .pan = drag { NSCursor.pop() }
        drag = nil
        render()
    }

    override func scrollWheel(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let precise = event.hasPreciseScrollingDeltas

        if event.modifierFlags.contains(.option), let current = imageSet.current, current.isLoaded {
            let factor = exp(event.scrollingDeltaY * (precise ? 0.0005 : 0.005))
            imageSet.scaleImage(current, by: factor, around: worldPoint(point))
            return
        }
        if precise && !event.modifierFlags.contains(.command) {
            pan(by: CGPoint(x: event.scrollingDeltaX, y: -event.scrollingDeltaY))
        } else {
            let steps = max(-5, min(5, precise ? event.scrollingDeltaY / 20 : event.scrollingDeltaY))
            setZoom(zoom * pow(1.15, steps), around: point)
        }
    }

    override func magnify(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if event.modifierFlags.contains(.option), let current = imageSet.current, current.isLoaded {
            imageSet.scaleImage(current, by: 1 + event.magnification * 0.1, around: worldPoint(point))
        } else {
            setZoom(zoom * (1 + event.magnification), around: point)
        }
    }

    override func smartMagnify(with event: NSEvent) {
        toggleFitOrActualPixels(at: convert(event.locationInWindow, from: nil))
    }

    override func flagsChanged(with event: NSEvent) {
        let held = event.modifierFlags.contains(.option)
        if held != optionHeld {
            optionHeld = held
            render()
        }
        super.flagsChanged(with: event)
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)
        NotificationCenter.default.removeObserver(self, name: NSWindow.didResignKeyNotification, object: nil)
        if let newWindow {
            NotificationCenter.default.addObserver(
                self, selector: #selector(windowDidResignKey),
                name: NSWindow.didResignKeyNotification, object: newWindow
            )
        }
    }

    @objc private func windowDidResignKey() {
        if optionHeld {
            optionHeld = false
            render()
        }
    }

    // MARK: - Keyboard

    override func keyDown(with event: NSEvent) {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if modifiers.contains(.command) || modifiers.contains(.control) {
            super.keyDown(with: event)
            return
        }
        let option = modifiers.contains(.option)
        let nudgeStep: CGFloat = modifiers.contains(.shift) ? 10 : 1

        switch event.keyCode {
        case 48: flipImages(nil); return
        case 51, 117: removeCurrentImage(nil); return
        case 53: escape(); return
        case 123: option ? nudge(-nudgeStep, 0) : previousImage(nil); return
        case 124: option ? nudge(nudgeStep, 0) : nextImage(nil); return
        case 125: option ? nudge(0, nudgeStep) : decreaseGain(nil); return
        case 126: option ? nudge(0, -nudgeStep) : increaseGain(nil); return
        default: break
        }

        guard let key = event.charactersIgnoringModifiers?.lowercased(), key.count == 1 else {
            super.keyDown(with: event)
            return
        }
        switch key {
        case "1"..."9": imageSet.select(index: Int(key)! - 1)
        case "0", "f": zoomToFit(nil)
        case "a": actualPixels(nil)
        case "=", "+": zoomIn(nil)
        case "-", "_": zoomOut(nil)
        case "s": toggleSplit(nil)
        case "d": toggleDifference(nil)
        case "p": togglePixelated(nil)
        case "o": toggleAlignOverlay(nil)
        case "r" where option: resetAlignment(nil)
        case "[": decreaseGain(nil)
        case "]": increaseGain(nil)
        case "n": toggleNoiseView(nil)
        case ",", "<": decreaseNoiseRadius(nil)
        case ".", ">": increaseNoiseRadius(nil)
        case "h", "?", "/": toggleHelp(nil)
        default: super.keyDown(with: event)
        }
    }

    private func nudge(_ dx: CGFloat, _ dy: CGFloat) {
        guard let current = imageSet.current, current.isLoaded else { return }
        imageSet.nudge(current, pixels: CGPoint(x: dx, y: dy))
    }

    private func escape() {
        if !helpLabel.isHidden {
            helpLabel.isHidden = true
        } else {
            imageSet.mode = .single
        }
    }

    // MARK: - Actions

    @objc func toggleSplit(_ sender: Any?) {
        imageSet.mode = imageSet.mode == .split ? .single : .split
    }

    @objc func toggleDifference(_ sender: Any?) {
        imageSet.mode = imageSet.mode == .difference ? .single : .difference
    }

    @objc func showSingle(_ sender: Any?) {
        imageSet.mode = .single
    }

    @objc func togglePixelated(_ sender: Any?) {
        imageSet.pixelated.toggle()
        flash(imageSet.pixelated ? "Pixels" : "Smooth")
    }

    @objc func toggleAlignOverlay(_ sender: Any?) {
        imageSet.alignOverlay = imageSet.alignOverlay == .difference ? .onion : .difference
        flash(imageSet.alignOverlay == .difference ? "Align overlay: Difference" : "Align overlay: Onion skin")
    }

    /// Adjusts the difference gain in difference view, otherwise the noise view strength.
    @objc func increaseGain(_ sender: Any?) {
        changeGain(by: 1)
    }

    @objc func decreaseGain(_ sender: Any?) {
        changeGain(by: -1)
    }

    private func changeGain(by delta: Int) {
        if imageSet.mode == .difference {
            imageSet.changeGain(by: delta)
        } else if imageSet.noiseView {
            imageSet.changeNoiseGain(by: delta)
            flash(noiseDescription)
        }
    }

    @objc func toggleNoiseView(_ sender: Any?) {
        imageSet.noiseView.toggle()
        flash(imageSet.noiseView ? noiseDescription : "Noise view off")
    }

    @objc func increaseNoiseRadius(_ sender: Any?) {
        guard imageSet.noiseView else { return }
        imageSet.changeNoiseRadius(by: 1)
        flash(noiseDescription)
    }

    @objc func decreaseNoiseRadius(_ sender: Any?) {
        guard imageSet.noiseView else { return }
        imageSet.changeNoiseRadius(by: -1)
        flash(noiseDescription)
    }

    @objc func zoomToFit(_ sender: Any?) {
        fit()
        render()
    }

    @objc func actualPixels(_ sender: Any?) {
        setZoom(actualPixelsZoom, around: zoomAnchor)
    }

    @objc func zoomIn(_ sender: Any?) {
        zoomStep(1)
    }

    @objc func zoomOut(_ sender: Any?) {
        zoomStep(-1)
    }

    @objc func nextImage(_ sender: Any?) {
        imageSet.step(1)
    }

    @objc func previousImage(_ sender: Any?) {
        imageSet.step(-1)
    }

    @objc func flipImages(_ sender: Any?) {
        imageSet.flip()
    }

    @objc func removeCurrentImage(_ sender: Any?) {
        if let current = imageSet.current { imageSet.remove(current) }
    }

    @objc func resetAlignment(_ sender: Any?) {
        guard let current = imageSet.current, current.isAdjusted else { return }
        imageSet.resetAlignment(current)
        flash("Alignment reset")
    }

    @objc func showInFinder(_ sender: Any?) {
        if let current = imageSet.current {
            NSWorkspace.shared.activateFileViewerSelecting([current.url])
        }
    }

    @objc func toggleHelp(_ sender: Any?) {
        helpLabel.isHidden.toggle()
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        let hasCurrent = imageSet.current != nil
        switch menuItem.action {
        case #selector(toggleSplit(_:)):
            menuItem.state = imageSet.mode == .split ? .on : .off
        case #selector(toggleDifference(_:)):
            menuItem.state = imageSet.mode == .difference ? .on : .off
        case #selector(showSingle(_:)):
            menuItem.state = imageSet.mode == .single ? .on : .off
        case #selector(togglePixelated(_:)):
            menuItem.state = imageSet.pixelated ? .on : .off
        case #selector(toggleAlignOverlay(_:)):
            menuItem.state = imageSet.alignOverlay == .onion ? .on : .off
        case #selector(toggleNoiseView(_:)):
            menuItem.state = imageSet.noiseView ? .on : .off
        case #selector(increaseGain(_:)), #selector(decreaseGain(_:)):
            return imageSet.mode == .difference || imageSet.noiseView
        case #selector(increaseNoiseRadius(_:)), #selector(decreaseNoiseRadius(_:)):
            return imageSet.noiseView
        case #selector(resetAlignment(_:)):
            return imageSet.current?.isAdjusted == true
        case #selector(nextImage(_:)), #selector(previousImage(_:)), #selector(flipImages(_:)):
            return imageSet.items.count > 1
        case #selector(removeCurrentImage(_:)), #selector(showInFinder(_:)):
            return hasCurrent
        default:
            break
        }
        return true
    }

    // MARK: - Drop

    private func droppedImages(_ info: NSDraggingInfo) -> [URL] {
        let urls = info.draggingPasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL] ?? []
        return ImageFiles.expand(urls)
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard !droppedImages(sender).isEmpty else { return [] }
        layer?.borderColor = NSColor.controlAccentColor.cgColor
        layer?.borderWidth = 3
        return .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        layer?.borderWidth = 0
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        layer?.borderWidth = 0
        let urls = droppedImages(sender)
        guard !urls.isEmpty else { return false }
        imageSet.add(urls)
        return true
    }
}
