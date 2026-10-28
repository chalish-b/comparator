// Helpers for scripts/screenshots.sh.
//
//   screenshot-tools scale        backing scale factor of the main display
//   screenshot-tools window PID   ID of the largest on-screen window of process PID
import AppKit

let arguments = CommandLine.arguments.dropFirst()

switch arguments.first {
case "scale":
    print(Int(NSScreen.main?.backingScaleFactor ?? 1))

case "window":
    guard let pid = arguments.dropFirst().first.flatMap({ Int32($0) }) else { exit(2) }
    let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
        as? [[String: Any]] ?? []
    let area = { (window: [String: Any]) -> CGFloat in
        let bounds = window[kCGWindowBounds as String] as? [String: CGFloat] ?? [:]
        return (bounds["Width"] ?? 0) * (bounds["Height"] ?? 0)
    }
    let largest = windows
        .filter { $0[kCGWindowOwnerPID as String] as? Int32 == pid && $0[kCGWindowLayer as String] as? Int == 0 }
        .max { area($0) < area($1) }
    guard let id = largest?[kCGWindowNumber as String] as? Int else { exit(1) }
    print(id)

default:
    FileHandle.standardError.write(Data("usage: screenshot-tools scale | window PID\n".utf8))
    exit(2)
}
