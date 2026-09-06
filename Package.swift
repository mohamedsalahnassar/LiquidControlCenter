// swift-tools-version: 6.3
import PackageDescription

let package = Package(
    name: "LiquidControlCenter",
    platforms: [.iOS(.v16), .macOS(.v13)],
    products: [.library(name: "LiquidControlCenter", targets: ["LiquidControlCenter"])],
    dependencies: [
        // Upstream has no release tags. Pin the audited public-API implementation.
        .package(url: "https://github.com/mohamedsalahnassar/LiquidGlassKit.git",
                 revision: "c1dd2276164446c1df417f96984749ab8e6d465a")
    ],
    targets: [
        .target(name: "LiquidControlCenter", dependencies: ["LiquidGlassKit"]),
        .testTarget(name: "LiquidControlCenterTests", dependencies: ["LiquidControlCenter"])
    ],
    swiftLanguageModes: [.v6]
)
