// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LiquidControlCenter",
    // macOS is declared only so the pure layout and motion tests run with `swift test`.
    platforms: [.iOS(.v16), .macOS(.v13)],
    products: [.library(name: "LiquidControlCenter", targets: ["LiquidControlCenter"])],
    dependencies: [
        // Tile glass: native Liquid Glass on iOS 26 and later, a material fallback before that.
        // Upstream has no release tags, so pin the reviewed revision. Its manifest requires Swift 6.3.
        .package(url: "https://github.com/mohamedsalahnassar/LiquidGlassKit.git",
                 revision: "c1dd2276164446c1df417f96984749ab8e6d465a")
    ],
    targets: [
        .target(name: "LiquidControlCenter", dependencies: ["LiquidGlassKit"]),
        .testTarget(name: "LiquidControlCenterTests", dependencies: ["LiquidControlCenter"])
    ],
    swiftLanguageModes: [.v6]
)
