import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// File and format details of an image, read from its file when it's decoded.
struct ImageInfo: Equatable, Sendable {
    /// Short format name, like "PNG" or "WebP".
    var format: String?
    var bitDepth: Int?
    /// "RGB", "Gray", "CMYK" or "Lab".
    var colorModel: String?
    var isIndexed = false
    var hasAlpha = false
    /// The embedded color profile's name, or nil if the file has none.
    var profile: String?
    var dpi: CGSize?
    var camera: String?
    var lens: String?
    var dateTaken: Date?

    init(source: CGImageSource, properties: [CFString: Any]?, image: CGImage) {
        if let identifier = CGImageSourceGetType(source) as String?, let type = UTType(identifier) {
            format = Self.formatName(type)
        }
        let properties = properties ?? [:]
        bitDepth = properties[kCGImagePropertyDepth] as? Int ?? image.bitsPerComponent
        colorModel = properties[kCGImagePropertyColorModel] as? String
        isIndexed = properties[kCGImagePropertyIsIndexed] as? Bool ?? false
        hasAlpha = properties[kCGImagePropertyHasAlpha] as? Bool
            ?? ![.none, .noneSkipFirst, .noneSkipLast].contains(image.alphaInfo)
        profile = properties[kCGImagePropertyProfileName] as? String

        if let width = properties[kCGImagePropertyDPIWidth] as? Double,
           let height = properties[kCGImagePropertyDPIHeight] as? Double {
            dpi = CGSize(width: width, height: height)
        }

        let tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any] ?? [:]
        let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any] ?? [:]
        camera = Self.cameraName(
            make: tiff[kCGImagePropertyTIFFMake] as? String,
            model: tiff[kCGImagePropertyTIFFModel] as? String
        )
        lens = (exif[kCGImagePropertyExifLensModel] as? String)?.trimmingCharacters(in: .whitespaces).nonEmpty
        dateTaken = (exif[kCGImagePropertyExifDateTimeOriginal] as? String).flatMap(Self.exifDate)
    }

    private static func formatName(_ type: UTType) -> String {
        switch type {
        case .jpeg: "JPEG"
        case .webP: "WebP"
        default: type.preferredFilenameExtension?.uppercased() ?? type.localizedDescription ?? type.identifier
        }
    }

    /// "Canon EOS R5" rather than "Canon Canon EOS R5".
    private static func cameraName(make: String?, model: String?) -> String? {
        let make = make?.trimmingCharacters(in: .whitespaces).nonEmpty
        let model = model?.trimmingCharacters(in: .whitespaces).nonEmpty
        guard let model else { return make }
        guard let make, !model.lowercased().hasPrefix(make.lowercased()) else { return model }
        return "\(make) \(model)"
    }

    private static func exifDate(_ string: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        return formatter.date(from: string)
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
