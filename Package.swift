// swift-tools-version: 6.3

import PackageDescription

let package = Package(
    name: "Comparator",
    platforms: [.macOS(.v15)],
    targets: [
        .executableTarget(name: "Comparator")
    ],
    swiftLanguageModes: [.v6]
)
