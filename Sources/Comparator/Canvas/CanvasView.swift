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
        case split(first: ImageItem, second: ImageItem)
        case difference(top: ImageItem, bottom: ImageItem?, gain: CGFloat)
        case onion(top: ImageItem, bottom: ImageItem?)
    }

    let imageSet: ComparisonSet

    private let host = LayerHostView()
    private let group = CALayer()
    private let firstClip = CALayer()
    private let secondClip = CALayer()
    private let divider = CALayer()
    private let knob = CALayer()
    private var imageLayers: [UUID: CALayer] = [:]

    private var zoom: CGFloat = 1000
    private var center = CGPoint(x: 0.5, y: 0.5)
    private var isFitted = true
    private var hadContent = false
    private var optionHeld = false
    private var drag: Drag?
    /// A zoom and center waiting for every image to load, since zoom percentages depend on
    /// image sizes.
    private var pendingView: (zoomPercent: CGFloat?, center: CGPoint?)?

    private let flashLabel = HUDLabel(fontSize: 12, weight: .medium)
    private let centerTag = HUDLabel(fontSize: 13, weight: .semibold)
    private let zoomPill = HUDLabel(fontSize: 11, monospacedDigits: true, symbol: "magnifyingglass")
    private let differencePill = HUDLabel(fontSize: 11, monospacedDigits: true, symbol: "circle.lefthalf.filled")
    private let aligningPill = HUDLabel(fontSize: 11, symbol: "move.3d")
    private let offsetPill = HUDLabel(
        fontSize: 11, monospacedDigits: true, symbol: "arrow.up.and.down.and.arrow.left.and.right"
    )
    private let scalePill = HUDLabel(
        fontSize: 11, monospacedDigits: true, symbol: "arrow.up.left.and.down.right.magnifyingglass"
    )
    private let noisePill = HUDLabel(fontSize: 11, monospacedDigits: true, symbol: "waveform.path")
    private let statusRow = NSStackView()
    private let firstTag = HUDLabel(fontSize: 12, weight: .medium)
    private let secondTag = HUDLabel(fontSize: 12, weight: .medium)
    private let messageLabel = HUDLabel(fontSize: 14, weight: .medium)
    private var firstTagLeading: NSLayoutConstraint!
    private var firstTagTrailing: NSLayoutConstraint!
    private var secondTagTop: NSLayoutConstraint!
    private var secondTagBottom: NSLayoutConstraint!
    private let helpLabel = HUDLabel(fontSize: 12, monospaced: true)
    private var flashTask: Task<Void, Never>?

    /// Canvas colours follow the system appearance: the under-page grey of Finder and Preview
    /// in light mode, a deep grey in dark mode. The split divider contrasts with the background.
    private static let background = NSColor(name: nil) { appearance in
        appearance.isDark ? NSColor(white: 0.11, alpha: 1) : .underPageBackgroundColor
    }
    private static let dividerColor = NSColor(name: nil) { appearance in
        appearance.isDark ? .white : NSColor(white: 0.15, alpha: 1)
    }

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
        for clip in [firstClip, secondClip] {
            clip.masksToBounds = true
            clip.anchorPoint = .zero
        }
        group.anchorPoint = .zero
        divider.shadowOpacity = 0.6
        divider.shadowRadius = 2
        divider.shadowOffset = .zero
        knob.cornerRadius = 7
        knob.shadowOpacity = 0.5
        knob.shadowRadius = 3
        knob.shadowOffset = .zero
        root.addSublayer(group)
        root.addSublayer(firstClip)
        root.addSublayer(secondClip)
        root.addSublayer(divider)
        root.addSublayer(knob)
        for layer in [group, firstClip, secondClip, divider, knob] {
            layer.actions = Self.noActions
        }
        applyAppearanceColors()
    }

    private func setUpHUD() {
        for label in [flashLabel, centerTag, firstTag, secondTag, messageLabel, helpLabel] {
            addSubview(label)
        }
        for pill in [zoomPill, aligningPill, offsetPill, scalePill, differencePill, noisePill] {
            statusRow.addArrangedSubview(pill)
        }
        statusRow.orientation = .horizontal
        statusRow.spacing = 6
        statusRow.alignment = .centerY
        statusRow.translatesAutoresizingMaskIntoConstraints = false
        statusRow.alphaValue = 0.85
        addSubview(statusRow)
        helpLabel.text = Self.helpText
        helpLabel.isHidden = true

        let safe = safeAreaLayoutGuide
        firstTagLeading = firstTag.leadingAnchor.constraint(equalTo: safe.leadingAnchor, constant: 12)
        firstTagTrailing = firstTag.trailingAnchor.constraint(equalTo: safe.trailingAnchor, constant: -12)
        secondTagTop = secondTag.topAnchor.constraint(equalTo: safe.topAnchor, constant: 12)
        secondTagBottom = secondTag.bottomAnchor.constraint(equalTo: safe.bottomAnchor, constant: -12)
        NSLayoutConstraint.activate([
            centerTag.centerXAnchor.constraint(equalTo: safe.centerXAnchor),
            centerTag.topAnchor.constraint(equalTo: safe.topAnchor, constant: 12),
            centerTag.widthAnchor.constraint(lessThanOrEqualTo: safe.widthAnchor, multiplier: 0.6),

            flashLabel.centerXAnchor.constraint(equalTo: safe.centerXAnchor),
            flashLabel.topAnchor.constraint(equalTo: safe.topAnchor, constant: 48),
            flashLabel.widthAnchor.constraint(lessThanOrEqualTo: safe.widthAnchor, multiplier: 0.5),

            statusRow.leadingAnchor.constraint(equalTo: safe.leadingAnchor, constant: 12),
            statusRow.bottomAnchor.constraint(equalTo: safe.bottomAnchor, constant: -12),
            statusRow.trailingAnchor.constraint(lessThanOrEqualTo: safe.trailingAnchor, constant: -12),

            firstTagLeading,
            firstTag.topAnchor.constraint(equalTo: safe.topAnchor, constant: 12),
            firstTag.widthAnchor.constraint(lessThanOrEqualTo: safe.widthAnchor, multiplier: 0.3),

            secondTag.trailingAnchor.constraint(equalTo: safe.trailingAnchor, constant: -12),
            secondTagTop,
            secondTag.widthAnchor.constraint(lessThanOrEqualTo: safe.widthAnchor, multiplier: 0.3),

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
        applyPendingView()

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

    /// The split divider's position within the visible area, which excludes the sidebar: its
    /// x coordinate side by side, its y coordinate when stacked.
    private var dividerPosition: CGFloat {
        let visible = safeAreaRect
        return switch imageSet.splitLayout {
        case .sideBySide: (visible.minX + visible.width * imageSet.splitPosition).rounded()
        case .stacked: (visible.maxY - visible.height * imageSet.splitPosition).rounded()
        }
    }

    /// A band of `thickness` centered on the split divider, spanning the view.
    private func dividerRect(thickness: CGFloat) -> CGRect {
        let position = dividerPosition
        return switch imageSet.splitLayout {
        case .sideBySide: CGRect(x: position - thickness / 2, y: 0, width: thickness, height: bounds.height)
        case .stacked: CGRect(x: 0, y: position - thickness / 2, width: bounds.width, height: thickness)
        }
    }

    /// Where a click or drag at `point` would put the split divider.
    private func splitPosition(at point: CGPoint) -> CGFloat {
        let visible = safeAreaRect
        let fraction = switch imageSet.splitLayout {
        case .sideBySide: (point.x - visible.minX) / visible.width
        case .stacked: (visible.maxY - point.y) / visible.height
        }
        return min(max(fraction, 0), 1)
    }

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

    /// Zooms to `zoomPercent` (or fits) and centers the visible area on `center`, given as
    /// fractions of the first image, once every image has loaded.
    func showView(zoomPercent: CGFloat?, center: CGPoint?) {
        guard zoomPercent != nil || center != nil else { return }
        pendingView = (zoomPercent, center)
        applyPendingView()
        render()
    }

    private func applyPendingView() {
        guard let pending = pendingView,
              imageSet.items.allSatisfy({ $0.isLoaded || $0.error != nil }),
              let reference = imageSet.reference, let content = imageSet.contentBounds
        else { return }
        pendingView = nil
        fit()
        if let percent = pending.zoomPercent {
            zoom = clampedZoom(actualPixelsZoom * percent / 100)
        }
        let frameHeight = reference.pixelSize.height / reference.pixelSize.width
        let target = pending.center.map { CGPoint(x: $0.x, y: $0.y * frameHeight) }
            ?? CGPoint(x: content.midX, y: content.midY)
        let visible = safeAreaRect
        center = CGPoint(
            x: target.x - (visible.midX - bounds.midX) / zoom,
            y: target.y + (visible.midY - bounds.midY) / zoom
        )
        isFitted = false
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

    private var mouseLocation: CGPoint? {
        window.map { convert($0.mouseLocationOutsideOfEventStream, from: nil) }
    }

    /// The mouse location if it's over the canvas, otherwise the center of the visible area.
    private var zoomAnchor: CGPoint {
        if let mouse = mouseLocation, bounds.contains(mouse) { return mouse }
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

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyAppearanceColors()
        render()
    }

    /// Resolves `color` for this view's current appearance.
    private func cgColor(_ color: NSColor) -> CGColor {
        var resolved = color.cgColor
        effectiveAppearance.performAsCurrentDrawingAppearance { resolved = color.cgColor }
        return resolved
    }

    private func applyAppearanceColors() {
        divider.backgroundColor = cgColor(Self.dividerColor)
        knob.backgroundColor = cgColor(Self.dividerColor)
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
            guard let pair = imageSet.splitPair else { return .single(current) }
            return .split(first: pair.first, second: pair.second)
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
        for layer in [root, group, firstClip, secondClip, divider, knob] {
            layer.contentsScale = scale
        }

        let liveIDs = Set(imageSet.items.map(\.id))
        for (id, layer) in imageLayers where !liveIDs.contains(id) {
            layer.removeFromSuperlayer()
            imageLayers[id] = nil
        }

        group.sublayers = nil
        firstClip.sublayers = nil
        secondClip.sublayers = nil
        group.filters = nil
        group.frame = bounds
        root.backgroundColor = cgColor(Self.background)
        var showsDivider = false

        let composite = composite()
        switch composite {
        case .empty:
            break

        case .single(let item):
            group.addSublayer(imageLayer(for: item, origin: .zero))

        case .split(let first, let second):
            let position = dividerPosition
            let knobCenter: CGPoint
            switch imageSet.splitLayout {
            case .sideBySide:
                firstClip.frame = CGRect(x: 0, y: 0, width: position, height: bounds.height)
                secondClip.frame = CGRect(x: position, y: 0, width: bounds.width - position, height: bounds.height)
                knobCenter = CGPoint(x: position, y: safeAreaRect.midY)
            case .stacked:
                firstClip.frame = CGRect(x: 0, y: position, width: bounds.width, height: bounds.height - position)
                secondClip.frame = CGRect(x: 0, y: 0, width: bounds.width, height: position)
                knobCenter = CGPoint(x: safeAreaRect.midX, y: position)
            }
            firstClip.addSublayer(imageLayer(for: first, origin: firstClip.frame.origin))
            secondClip.addSublayer(imageLayer(for: second, origin: secondClip.frame.origin))
            divider.frame = dividerRect(thickness: 1)
            knob.frame = CGRect(x: knobCenter.x - 7, y: knobCenter.y - 7, width: 14, height: 14)
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

        firstClip.isHidden = !showsDivider
        secondClip.isHidden = !showsDivider
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

    /// The image's number, styled like the sidebar's key, followed by its name, after an
    /// optional SF Symbol.
    private func tag(for item: ImageItem, in label: HUDLabel, symbol: String? = nil) -> NSAttributedString {
        let tag = NSMutableAttributedString()
        if let symbol, let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: label.font.pointSize, weight: .medium)) {
            let attachment = NSTextAttachment()
            attachment.image = image
            tag.append(NSAttributedString(attachment: attachment))
            tag.append(NSAttributedString(string: "  "))
        }
        let number = (imageSet.index(of: item) ?? 0) + 1
        tag.append(NSAttributedString(string: "\(number)", attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: label.font.pointSize, weight: .semibold),
            .foregroundColor: NSColor.secondaryLabelColor,
        ]))
        tag.append(NSAttributedString(string: "  " + item.name))
        return tag
    }

    private func tag(for top: ImageItem, _ joiner: String, _ bottom: ImageItem?, in label: HUDLabel) -> NSAttributedString {
        let combined = NSMutableAttributedString(attributedString: tag(for: top, in: label))
        if let bottom {
            combined.append(NSAttributedString(string: joiner))
            combined.append(tag(for: bottom, in: label))
        }
        return combined
    }

    private func updateHUD(_ composite: Composite) {
        if imageSet.items.isEmpty {
            messageLabel.text = "Drop images here"
        } else if let current = imageSet.current, !current.isLoaded {
            messageLabel.text = current.error.map { "Couldn't open \(current.name)\n\($0)" } ?? "Loading \(current.name)…"
        } else {
            messageLabel.text = nil
        }

        firstTag.text = nil
        secondTag.text = nil
        centerTag.text = nil
        // Side by side, the tags sit in the top corners; stacked, in the right corners.
        let stacked = imageSet.splitLayout == .stacked
        NSLayoutConstraint.deactivate(stacked ? [firstTagLeading, secondTagTop] : [firstTagTrailing, secondTagBottom])
        NSLayoutConstraint.activate(stacked ? [firstTagTrailing, secondTagBottom] : [firstTagLeading, secondTagTop])
        switch composite {
        case .empty:
            break
        case .single(let item):
            centerTag.attributedText = tag(for: item, in: centerTag)
        case .split(let first, let second):
            firstTag.attributedText = tag(for: first, in: firstTag, symbol: splitTagSymbol(for: first))
            secondTag.attributedText = tag(for: second, in: secondTag, symbol: splitTagSymbol(for: second))
        case .difference(let top, let bottom, _):
            centerTag.attributedText = tag(for: top, "  −  ", bottom, in: centerTag)
        case .onion(let top, let bottom):
            centerTag.attributedText = tag(for: top, "  over  ", bottom, in: centerTag)
        }

        updateStatusRow(composite)
    }

    /// A pin on the pinned image; without one, a mark on the image the next selection replaces.
    private func splitTagSymbol(for item: ImageItem) -> String? {
        if imageSet.pinned != nil {
            return item === imageSet.pinned ? "pin.fill" : nil
        }
        return imageSet.side(of: item) == imageSet.nextSplitSide ? "arrow.right" : nil
    }

    private func updateStatusRow(_ composite: Composite) {
        for pill in [zoomPill, aligningPill, offsetPill, scalePill, differencePill, noisePill] {
            pill.text = nil
        }
        if case .empty = composite { return }
        zoomPill.text = Self.format(percent: zoomPercent)

        if isAligning, let current = imageSet.current {
            let unit = imageSet.worldPerPixel(current)
            let dx = unit > 0 ? current.offset.x / unit : 0
            let dy = unit > 0 ? current.offset.y / unit : 0
            aligningPill.text = "Aligning"
            offsetPill.text = String(format: "%+.1f, %+.1f px", dx, dy)
            scalePill.text = String(format: "%.2f%%", current.scale * 100)
        } else if case .difference(_, _, let gain) = composite {
            differencePill.text = "×\(Int(gain))"
        }
        if imageSet.noiseView {
            noisePill.text = noiseDescription + (imageSet.isComputingNoise ? " (updating…)" : "")
        }
    }

    private var noiseDescription: String {
        "×\(Int(imageSet.noiseGain)), radius \(Int(imageSet.noiseRadius)) px"
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
        1–9          Show image (split: on alternating sides)
        Tab          Flip to last viewed image
        ↑ ↓          Previous / next image
        L            Pin / unpin image
        `            Show pinned image
        X            Swap split sides
        S            Split view
        ⇧S           Rotate split
        D            Difference view
        N            Noise view
        [ ]          Difference gain / noise strength
        , .          Noise radius
        P            Pixels / smooth
        0 or F       Fit
        A            Actual pixels (100%)
        + −          Zoom in / out
        Double-click Fit / 100%
        Drag         Pan

        Hold ⌥       Alignment overlay (split: image under pointer)
        ⌥ drag       Move image
        ⌥ arrows     Nudge 1 px (⇧ for 0.1 px)
        ⌥ scroll     Scale image
        ⌥ R          Reset alignment
        O            Overlay: difference / onion skin

        ⌫            Remove image from set
        I            Show / hide info
        H            Show / hide this help

        ⌘T           New set
        ⌘O           Open images as a new set
        ⇧⌘O          Add images to this set
        ⌘S           Show / hide sidebar
        """

    // MARK: - Mouse

    override var acceptsFirstResponder: Bool { true }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func resetCursorRects() {
        if case .split = composite() {
            let cursor: NSCursor = imageSet.splitLayout == .sideBySide ? .resizeLeftRight : .resizeUpDown
            addCursorRect(dividerRect(thickness: 10), cursor: cursor)
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
            selectSplitImage(at: point)
            drag = .align(last: point)
            render()
            return
        }
        if case .split = composite(), dividerRect(thickness: 12).contains(point) {
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
            imageSet.splitPosition = splitPosition(at: point)
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
            if held, let mouse = mouseLocation { selectSplitImage(at: mouse) }
            optionHeld = held
            render()
        }
        super.flagsChanged(with: event)
    }

    /// In split view, makes the image on the half under `point` the current one without moving
    /// it, so alignment moves the image you point at.
    private func selectSplitImage(at point: CGPoint) {
        guard case .split(let first, let second) = composite(), safeAreaRect.contains(point) else { return }
        let inFirst = switch imageSet.splitLayout {
        case .sideBySide: point.x < dividerPosition
        case .stacked: point.y >= dividerPosition
        }
        imageSet.focus(inFirst ? first : second)
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
        let shift = modifiers.contains(.shift)
        let nudgeStep: CGFloat = shift ? 0.1 : 1

        switch event.keyCode {
        case 48: flipImages(nil); return
        case 51, 117: removeCurrentImage(nil); return
        case 53: escape(); return
        case 123 where option: nudge(-nudgeStep, 0); return
        case 124 where option: nudge(nudgeStep, 0); return
        case 125: option ? nudge(0, nudgeStep) : nextImage(nil); return
        case 126: option ? nudge(0, -nudgeStep) : previousImage(nil); return
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
        case "s" where shift: rotateSplit(nil)
        case "s": toggleSplit(nil)
        case "d": toggleDifference(nil)
        case "p": togglePixelated(nil)
        case "o": toggleAlignOverlay(nil)
        case "l": togglePin(nil)
        case "`": togglePinnedImage(nil)
        case "x": swapSides(nil)
        case "r" where option: resetAlignment(nil)
        case "[": decreaseGain(nil)
        case "]": increaseGain(nil)
        case "n": toggleNoiseView(nil)
        case ",", "<": decreaseNoiseRadius(nil)
        case ".", ">": increaseNoiseRadius(nil)
        case "h", "?", "/": toggleHelp(nil)
        case "i": NSApp.sendAction(#selector(ComparisonWindowController.toggleInfo(_:)), to: nil, from: self)
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

    /// Switches between side-by-side and stacked split view, entering split view if needed.
    @objc func rotateSplit(_ sender: Any?) {
        imageSet.splitLayout = imageSet.splitLayout == .sideBySide ? .stacked : .sideBySide
        imageSet.mode = .split
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
            flash("Noise " + noiseDescription)
        }
    }

    @objc func toggleNoiseView(_ sender: Any?) {
        imageSet.noiseView.toggle()
        flash(imageSet.noiseView ? "Noise " + noiseDescription : "Noise view off")
    }

    @objc func increaseNoiseRadius(_ sender: Any?) {
        guard imageSet.noiseView else { return }
        imageSet.changeNoiseRadius(by: 1)
        flash("Noise " + noiseDescription)
    }

    @objc func decreaseNoiseRadius(_ sender: Any?) {
        guard imageSet.noiseView else { return }
        imageSet.changeNoiseRadius(by: -1)
        flash("Noise " + noiseDescription)
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
        imageSet.showPrevious()
    }

    @objc func swapSides(_ sender: Any?) {
        guard imageSet.mode == .split else { return }
        imageSet.swapSides()
    }

    @objc func togglePinnedImage(_ sender: Any?) {
        imageSet.togglePinnedFocus()
    }

    @objc func togglePin(_ sender: Any?) {
        guard let current = imageSet.current else { return }
        imageSet.togglePin(current)
        flash(imageSet.pinned === current ? "Pinned \(current.name)" : "Unpinned \(current.name)")
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
        case #selector(flipImages(_:)):
            return imageSet.items.count > 1
        case #selector(swapSides(_:)):
            return imageSet.mode == .split && imageSet.other != nil
        case #selector(togglePinnedImage(_:)):
            menuItem.state = imageSet.mode == .single && imageSet.pinned != nil && imageSet.pinned === imageSet.current ? .on : .off
            return imageSet.mode == .single && imageSet.pinned != nil && imageSet.other != nil
        case #selector(togglePin(_:)):
            menuItem.title = imageSet.pinned != nil && imageSet.pinned === imageSet.current ? "Unpin Image" : "Pin Image"
            return hasCurrent
        case #selector(nextImage(_:)), #selector(previousImage(_:)):
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

private extension NSAppearance {
    var isDark: Bool { bestMatch(from: [.aqua, .darkAqua]) == .darkAqua }
}
