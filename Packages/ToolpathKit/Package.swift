// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "ToolpathKit",
    defaultLocalization: "en",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "CNCKit", targets: ["CNCKit"]),
        .library(name: "CNCDesign", targets: ["CNCDesign"]),
        .library(name: "CNCRender", targets: ["CNCRender"]),
    ],
    targets: [
        // Pure, deterministic CNC logic. No UI, no networking, no persistence.
        .target(
            name: "CNCKit",
            resources: [.process("Resources")]
        ),
        // Design tokens and shared SwiftUI components.
        .target(name: "CNCDesign"),
        // Toolpath drawing (2D Canvas, 3D Metal) and orbit camera.
        .target(name: "CNCRender", dependencies: ["CNCKit", "CNCDesign"], resources: [.process("Resources")]),
        .testTarget(
            name: "CNCKitTests",
            dependencies: ["CNCKit"],
            resources: [.copy("Fixtures")]
        ),
        .testTarget(name: "CNCRenderTests", dependencies: ["CNCRender"]),
    ]
)
