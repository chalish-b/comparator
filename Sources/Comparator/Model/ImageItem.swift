import AppKit

/// One image in a comparison set, plus its placement adjustments.
@MainActor
final class ImageItem {
    let id = UUID()
    let url: URL

    var image: CGImage?
    var thumbnail: NSImage?
    var pixelSize: CGSize = .zero
    var stamp: FileStamp?
    var info: ImageInfo?
    var error: String?

    /// Translation applied on top of the default placement, in world units (the reference frame is 1 unit wide).
    var offset: CGPoint = .zero
    /// Scale applied on top of the default placement, around the image's center.
    var scale: CGFloat = 1

    /// The noise view of `image`, and the settings it was computed with.
    var noise: (key: NoiseKey, image: CGImage)?
    var pendingNoiseKey: NoiseKey?
    var failedNoiseKey: NoiseKey?

    /// Incremented per load request so stale decodes are dropped.
    var generation = 0
    var failedReloads = 0

    init(url: URL) {
        self.url = url
    }

    var name: String { url.lastPathComponent }
    var isLoaded: Bool { image != nil }
    var isAdjusted: Bool { offset != .zero || scale != 1 }
}

/// The inputs a noise view image was computed from.
struct NoiseKey: Equatable, Sendable {
    let sigma: CGFloat
    let gain: CGFloat
    let source: ObjectIdentifier
}

/// Modification date and size, used to detect when a file changed on disk.
struct FileStamp: Equatable, Sendable {
    let modified: Date
    let size: Int

    static func of(_ url: URL) -> FileStamp? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let modified = attributes[.modificationDate] as? Date,
              let size = attributes[.size] as? Int
        else { return nil }
        return FileStamp(modified: modified, size: size)
    }
}
