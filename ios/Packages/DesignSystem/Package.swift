// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DesignSystem",
    defaultLocalization: "en",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "DesignSystem", targets: ["DesignSystem"]),
        // In-repo snapshot helper used by test targets only (no third-party library).
        .library(name: "SnapshotSupport", targets: ["SnapshotSupport"]),
    ],
    dependencies: [],
    targets: [
        .target(
            name: "DesignSystem",
            dependencies: [],
            resources: [.copy("Resources/Fonts")]
        ),
        .target(name: "SnapshotSupport", dependencies: []),
        .testTarget(
            name: "DesignSystemTests",
            dependencies: ["DesignSystem", "SnapshotSupport"],
            exclude: ["__Snapshots__"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
