// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "QRCode",
    defaultLocalization: "en",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "QRCode", targets: ["QRCode"]),
    ],
    dependencies: [
        .package(path: "../Core"),
        .package(path: "../DesignSystem"),
    ],
    targets: [
        .target(name: "QRCode", dependencies: ["Core", "DesignSystem"]),
        .testTarget(name: "QRCodeTests", dependencies: ["QRCode"]),
    ],
    swiftLanguageModes: [.v6]
)
