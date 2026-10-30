import Foundation

/// Images to open as a new set, with the view to show them in. The command-line tool sends one
/// to the app as a URL in the app's own scheme.
struct OpenRequest {
    var files: [URL] = []
    var mode: ViewMode?
    var splitLayout: SplitLayout?
    var swapped = false
    /// Images to select in order, numbered from 1; the last one becomes current.
    var show: [Int] = []
    /// The image to pin, numbered from 1.
    var pin: Int?
    var zoomPercent: CGFloat?
    /// View center as fractions of the first image's width and height, from its top left.
    var center: CGPoint?
    var divider: CGFloat?
    var pixelated: Bool?

    /// The URL scheme in the Info.plist of the app at `bundleURL`.
    static func scheme(ofAppAt bundleURL: URL) -> String? {
        let types = Bundle(url: bundleURL)?.object(forInfoDictionaryKey: "CFBundleURLTypes") as? [[String: Any]]
        return (types?.first?["CFBundleURLSchemes"] as? [String])?.first
    }

    func url(scheme: String) -> URL {
        var components = URLComponents()
        components.scheme = scheme
        components.host = "open"
        var items = files.map { URLQueryItem(name: "file", value: $0.path) }
        if let mode {
            items.append(URLQueryItem(name: "mode", value: mode == .difference ? "difference" : mode == .split ? "split" : "single"))
        }
        if splitLayout == .stacked { items.append(URLQueryItem(name: "layout", value: "stacked")) }
        if swapped { items.append(URLQueryItem(name: "swap", value: "1")) }
        if !show.isEmpty { items.append(URLQueryItem(name: "show", value: show.map(String.init).joined(separator: ","))) }
        if let pin { items.append(URLQueryItem(name: "pin", value: "\(pin)")) }
        if let zoomPercent { items.append(URLQueryItem(name: "zoom", value: "\(zoomPercent)")) }
        if let center { items.append(URLQueryItem(name: "center", value: "\(center.x),\(center.y)")) }
        if let divider { items.append(URLQueryItem(name: "divider", value: "\(divider)")) }
        if let pixelated { items.append(URLQueryItem(name: "pixels", value: pixelated ? "1" : "0")) }
        components.queryItems = items
        return components.url!
    }

    init() {}

    init?(url: URL) {
        guard url.host == "open", let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems else {
            return nil
        }
        for item in items {
            guard let value = item.value else { continue }
            switch item.name {
            case "file": files.append(URL(fileURLWithPath: value))
            case "mode": mode = value == "difference" ? .difference : value == "split" ? .split : .single
            case "layout": splitLayout = value == "stacked" ? .stacked : .sideBySide
            case "swap": swapped = value == "1"
            case "show": show = value.split(separator: ",").compactMap { Int($0) }
            case "pin": pin = Int(value)
            case "zoom": zoomPercent = Double(value).map { CGFloat($0) }
            case "center": center = Self.point(value)
            case "divider": divider = Double(value).map { CGFloat($0) }
            case "pixels": pixelated = value == "1"
            default: break
            }
        }
    }

    /// Parses "x,y".
    static func point(_ text: String) -> CGPoint? {
        let parts = text.split(separator: ",").compactMap { Double($0) }
        guard parts.count == 2 else { return nil }
        return CGPoint(x: parts[0], y: parts[1])
    }
}
