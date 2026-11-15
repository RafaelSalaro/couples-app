// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Purchases",
    defaultLocalization: "en",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "Purchases", targets: ["Purchases"]),
    ],
    dependencies: [
        .package(path: "../Core"),
        .package(url: "https://github.com/RevenueCat/purchases-ios-spm.git", from: "5.0.0"),
    ],
    targets: [
        .target(name: "Purchases", dependencies: [
            "Core",
            .product(name: "RevenueCat", package: "purchases-ios-spm"),
        ], resources: [.process("Resources")]),
        .testTarget(name: "PurchasesTests", dependencies: ["Purchases"]),
    ],
    swiftLanguageModes: [.v6]
)
