// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "Localix",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "Localix",
            path: "Sources/Localix"
        )
    ]
)
