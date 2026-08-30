// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "YouShot",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .executable(name: "YouShot", targets: ["YouShot"]),
    ],
    targets: [
        .executableTarget(
            name: "YouShot",
            path: "Sources/YouShot"
        ),
    ]
)
