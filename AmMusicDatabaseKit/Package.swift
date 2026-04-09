// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "AmMusicDatabaseKit",
    defaultLocalization: "en",
    platforms: [
        .iOS(.v15),
        .macOS(.v12),
    ],
    products: [
        .library(
            name: "AmMusicDatabaseKit",
            targets: ["AmMusicDatabaseKit"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/Lakr233/wcdb-spm-prebuilt", from: "2.1.10"),
    ],
    targets: [
        .target(
            name: "AmMusicDatabaseKit",
            dependencies: [
                .product(name: "WCDBSwift", package: "wcdb-spm-prebuilt"),
            ],
            resources: [
                .process("Resources"),
            ]
        ),
        .testTarget(
            name: "AmMusicDatabaseKitTests",
            dependencies: [
                "AmMusicDatabaseKit",
            ]
        ),
    ],
    swiftLanguageModes: [.v6]
)
