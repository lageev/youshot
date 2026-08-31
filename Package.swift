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
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle.git", exact: "2.9.6"),
    ],
    targets: [
        .executableTarget(
            name: "YouShot",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            path: "Sources/YouShot",
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker", "-rpath",
                    "-Xlinker", "@executable_path/../Frameworks",
                ]),
            ]
        ),
    ]
)
