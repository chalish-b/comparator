// swift-tools-version: 6.3

import PackageDescription

let package = Package(
    name: "ImgCompare",
    platforms: [.macOS(.v15)],
    targets: [
        .executableTarget(name: "ImgCompare")
    ],
    swiftLanguageModes: [.v6]
)
