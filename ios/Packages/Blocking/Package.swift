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
    ],
    targets: [
        .target(name: "Blocking", dependencies: ["Core"]),
        .testTarget(name: "BlockingTests", dependencies: ["Blocking"]),
    ],
    swiftLanguageModes: [.v6]
)
