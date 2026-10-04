// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LiquidControlCenter",
    // macOS is declared only so the pure layout and motion tests run with `swift test`.
    platforms: [.iOS(.v16), .macOS(.v13)],
    products: [.library(name: "LiquidControlCenter", targets: ["LiquidControlCenter"])],
    targets: [
        .target(name: "LiquidControlCenter"),
        .testTarget(name: "LiquidControlCenterTests", dependencies: ["LiquidControlCenter"])
    ],
    swiftLanguageModes: [.v6]
)
