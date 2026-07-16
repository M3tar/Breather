// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Breather",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .executable(name: "Breather", targets: ["Breather"])
    ],
    targets: [
        .executableTarget(
            name: "Breather",
            path: "Sources/Breather",
            resources: [
                .process("Resources")
            ]
        )
    ]
)
