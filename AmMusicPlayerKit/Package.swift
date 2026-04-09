// swift-tools-version: 6.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "AmMusicPlayerKit",
    defaultLocalization: "en",
    platforms: [.iOS(.v15), .macOS(.v12)],
    products: [
        .library(
            name: "AmMusicPlayerKit",
            targets: ["AmMusicPlayerKit"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/onevcat/Kingfisher.git", from: "8.0.0"),
    ],
    targets: [
        .target(
            name: "AmMusicPlayerKit",
            dependencies: ["Kingfisher"],
            resources: [
                .process("Resources"),
            ]
        ),
        .testTarget(
            name: "AmMusicPlayerKitTests",
            dependencies: ["AmMusicPlayerKit"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
