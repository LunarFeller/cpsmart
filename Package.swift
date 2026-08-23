// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "cpsmart",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "cpsmart", targets: ["cpsmart"])
    ],
    targets: [
        .executableTarget(
            name: "cpsmart",
            path: "Sources/cpsmart"
        )
    ]
)
