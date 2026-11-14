// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Blocking",
    defaultLocalization: "en",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "Blocking", targets: ["Blocking"]),
    ],
    dependencies: [
        .package(path: "../Core"),
        .package(path: "../DesignSystem"),
    ],
    targets: [
        .target(name: "Blocking", dependencies: ["Core", "DesignSystem"], resources: [.process("Resources")]),
        .testTarget(name: "BlockingTests", dependencies: ["Blocking"]),
    ],
    swiftLanguageModes: [.v6]
)
