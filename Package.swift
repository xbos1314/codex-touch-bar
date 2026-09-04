// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CodexTouchBar",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "CodexTouchBarCore", targets: ["CodexTouchBarCore"]),
        .executable(name: "CodexTouchBarApp", targets: ["CodexTouchBarApp"])
    ],
    targets: [
        .target(name: "CodexTouchBarCore"),
        .executableTarget(
            name: "CodexTouchBarApp",
            dependencies: ["CodexTouchBarCore"]
        )
    ]
)
