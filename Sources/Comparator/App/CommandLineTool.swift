import AppKit

/// `comparator [options] [images or folders…]`. Run from a shell, the executable passes its
/// arguments to the app, launching it if needed, and exits, so the app runs on its own.
enum CommandLineTool {
    /// Whether the process was started from a shell. Finder, the Dock and `open` launch apps
    /// through launchd.
    static var isInvoked: Bool { getppid() != 1 }

    private struct UsageError: Error {
        let message: String
    }

    private static var name: String {
        URL(fileURLWithPath: CommandLine.arguments[0]).lastPathComponent
    }

    private static var usage: String {
        """
        Usage: \(name) [options] [images or folders…]

        Opens the images as a new set in Comparator, launching it if needed.

        Options:
          --split         Split view, side by side
          --stacked       Split view, stacked
          --difference    Difference view
          --swap          Swap the split sides
          --show A[,B]    Show image A, or images A and B with B as the current one
                          (numbered from 1, like the 1–9 keys)
          --zoom N        Zoom percent, e.g. 400 (default: fit)
          --center X,Y    Center the view on this point of the first image, as fractions
                          of its size from 0,0 (top left) to 1,1 (bottom right)
          --divider F     Split divider position, from 0 to 1
          --pixels        Show pixels when zoomed in
          --smooth        Smooth images when zoomed in
          -h, --help      Show this help
        """
    }

    static func run() -> Never {
        do {
            let arguments = Array(CommandLine.arguments.dropFirst())
            if arguments.contains(where: { $0 == "-h" || $0 == "--help" }) {
                print(usage)
                exit(0)
            }
            try send(parse(arguments))
            exit(0)
        } catch let error as UsageError {
            FileHandle.standardError.write(Data("\(name): \(error.message)\nRun '\(name) --help' for usage.\n".utf8))
            exit(1)
        } catch {
            FileHandle.standardError.write(Data("\(name): \(error.localizedDescription)\n".utf8))
            exit(1)
        }
    }

    // MARK: - Parsing

    private static func parse(_ arguments: [String]) throws -> OpenRequest {
        var request = OpenRequest()
        var remaining = arguments[...]
        var onlyFiles = false

        func value(for option: String, inline: String?) throws -> String {
            if let inline { return inline }
            guard let next = remaining.popFirst() else { throw UsageError(message: "\(option) needs a value") }
            return next
        }

        func setMode(_ mode: ViewMode, _ layout: SplitLayout?, option: String) throws {
            guard request.mode == nil else { throw UsageError(message: "\(option) can't be combined with another view") }
            request.mode = mode
            request.splitLayout = layout
        }

        while let argument = remaining.popFirst() {
            guard !onlyFiles, argument.hasPrefix("-") else {
                request.files += try images(at: argument)
                continue
            }
            let parts = argument.split(separator: "=", maxSplits: 1).map(String.init)
            let option = parts[0]
            let inline = parts.count > 1 ? parts[1] : nil

            switch option {
            case "--":
                onlyFiles = true
            case "--split":
                try setMode(.split, .sideBySide, option: option)
            case "--stacked":
                try setMode(.split, .stacked, option: option)
            case "--difference":
                try setMode(.difference, nil, option: option)
            case "--swap":
                request.swapped = true
            case "--pixels":
                request.pixelated = true
            case "--smooth":
                request.pixelated = false
            case "--show":
                let text = try value(for: option, inline: inline)
                let numbers = text.split(separator: ",").map { Int($0) }
                guard (1...2).contains(numbers.count), numbers.allSatisfy({ ($0 ?? 0) >= 1 }) else {
                    throw UsageError(message: "--show takes one or two image numbers, like 1,2")
                }
                request.show = numbers.compactMap { $0 }
            case "--zoom":
                let text = try value(for: option, inline: inline)
                guard let percent = Double(text.hasSuffix("%") ? String(text.dropLast()) : text), percent > 0 else {
                    throw UsageError(message: "--zoom takes a percentage, like 400")
                }
                request.zoomPercent = percent
            case "--center":
                guard let point = OpenRequest.point(try value(for: option, inline: inline)) else {
                    throw UsageError(message: "--center takes two fractions, like 0.5,0.25")
                }
                request.center = point
            case "--divider":
                guard let fraction = Double(try value(for: option, inline: inline)), (0...1).contains(fraction) else {
                    throw UsageError(message: "--divider takes a fraction from 0 to 1")
                }
                request.divider = fraction
            default:
                throw UsageError(message: "unknown option \(option)")
            }
        }

        if let highest = request.show.max(), highest > request.files.count {
            throw UsageError(message: "--show \(highest) is past the last image (\(request.files.count) opened)")
        }
        return request
    }

    /// The image at `path`, or the images in it if it's a folder.
    private static func images(at path: String) throws -> [URL] {
        let url = URL(fileURLWithPath: path).standardizedFileURL
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            throw UsageError(message: "no such file: \(path)")
        }
        let images = ImageFiles.expand([url])
        if images.isEmpty {
            throw UsageError(message: isDirectory.boolValue ? "no images in \(path)" : "not an image: \(path)")
        }
        return images
    }

    // MARK: - Sending

    private final class Result: @unchecked Sendable {
        var error: (any Error)?
    }

    /// The app bundle containing this executable, following a symlink to it.
    private static var bundleURL: URL? {
        let executable = Bundle.main.executableURL?.resolvingSymlinksInPath()
        let bundle = executable?.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return bundle?.pathExtension == "app" ? bundle : nil
    }

    private static func send(_ request: OpenRequest) throws {
        guard let bundleURL else { throw UsageError(message: "can't find Comparator.app around this executable") }
        let configuration = NSWorkspace.OpenConfiguration()
        let result = Result()
        let done = DispatchSemaphore(value: 0)

        if request.files.isEmpty {
            NSWorkspace.shared.openApplication(at: bundleURL, configuration: configuration) { _, error in
                result.error = error
                done.signal()
            }
        } else {
            guard let scheme = OpenRequest.scheme(ofAppAt: bundleURL) else {
                throw UsageError(message: "the app at \(bundleURL.path) has no URL scheme")
            }
            NSWorkspace.shared.open([request.url(scheme: scheme)], withApplicationAt: bundleURL, configuration: configuration) { _, error in
                result.error = error
                done.signal()
            }
        }
        done.wait()
        if let error = result.error { throw error }
    }
}
