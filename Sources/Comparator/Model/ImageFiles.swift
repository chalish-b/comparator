import Foundation
import UniformTypeIdentifiers

enum ImageFiles {
    /// Image files among `urls`, with folders replaced by the images directly inside them.
    /// The result is sorted by filename so numbered outputs land in order.
    static func expand(_ urls: [URL]) -> [URL] {
        var result: [URL] = []
        for url in urls {
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey])
            if values?.isDirectory == true {
                let children = (try? FileManager.default.contentsOfDirectory(
                    at: url,
                    includingPropertiesForKeys: [.contentTypeKey],
                    options: [.skipsHiddenFiles]
                )) ?? []
                result += children.filter(isImage)
            } else if isImage(url) {
                result.append(url)
            }
        }
        return result.sorted {
            $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending
        }
    }

    static func isImage(_ url: URL) -> Bool {
        guard let type = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType else { return false }
        return type.conforms(to: .image)
    }
}
