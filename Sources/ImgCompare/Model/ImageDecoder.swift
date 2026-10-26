import CoreImage
import Foundation
import ImageIO

struct DecodedImage: @unchecked Sendable {
    let image: CGImage
    let thumbnail: CGImage?
    let stamp: FileStamp?
}

enum DecodeError: LocalizedError {
    case unreadable
    case incomplete

    var errorDescription: String? {
        switch self {
        case .unreadable: "Unsupported or unreadable image"
        case .incomplete: "The file is incomplete"
        }
    }
}

/// Fully decodes images off the main thread so switching between them is instant.
enum ImageDecoder {
    private static let ciContext = CIContext(options: [.cacheIntermediates: false])

    static func decode(_ url: URL) throws -> DecodedImage {
        let stamp = FileStamp.of(url)
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              CGImageSourceGetCount(source) > 0
        else { throw DecodeError.unreadable }
        guard CGImageSourceGetStatus(source) == .statusComplete else { throw DecodeError.incomplete }

        let options = [kCGImageSourceShouldCacheImmediately: true] as CFDictionary
        guard var image = CGImageSourceCreateImageAtIndex(source, 0, options) else {
            throw DecodeError.unreadable
        }

        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        if let raw = properties?[kCGImagePropertyOrientation] as? UInt32,
           raw != 1,
           let orientation = CGImagePropertyOrientation(rawValue: raw),
           let oriented = orient(image, orientation) {
            image = oriented
        }

        let thumbnailOptions = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 160,
        ] as CFDictionary
        let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions)

        return DecodedImage(image: image, thumbnail: thumbnail, stamp: stamp)
    }

    private static func orient(_ image: CGImage, _ orientation: CGImagePropertyOrientation) -> CGImage? {
        let oriented = CIImage(cgImage: image).oriented(orientation)
        let colorSpace = image.colorSpace.flatMap { $0.model == .rgb ? $0 : nil }
            ?? CGColorSpace(name: CGColorSpace.sRGB)!
        let format: CIFormat = image.bitsPerComponent > 8 ? .RGBAh : .RGBA8
        return ciContext.createCGImage(oriented, from: oriented.extent, format: format, colorSpace: colorSpace)
    }
}
