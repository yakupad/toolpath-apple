// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "ToolpathKit",
    defaultLocalization: "en",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "CNCKit", targets: ["CNCKit"]),
    ],
    targets: [
        // Pure, deterministic CNC logic. No UI, no networking, no persistence.
        .target(
            name: "CNCKit",
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "CNCKitTests",
            dependencies: ["CNCKit"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
