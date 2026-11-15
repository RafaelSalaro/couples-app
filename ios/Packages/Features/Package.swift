// swift-tools-version: 6.0
import PackageDescription

// One library per feature. Module names carry a "Feature" suffix so they never
// collide with model types such as `Schedule` or `Settings`.
// `FeatureSupport` holds what every feature shares: the app model, dependencies and common views.
let features = [
    "Onboarding", "Pairing", "Home", "Unlock", "Minutes",
    "Challenges", "Kudos", "Reports", "Schedule", "Settings",
]

/// Features that reuse another feature's screens.
let featureDependencies: [String: [String]] = [
    "Onboarding": ["Pairing"],
    "Settings": ["Pairing", "Minutes"],
]

let shared: [Target.Dependency] = [
    "Core", "DesignSystem", "Backend", "Blocking", "QRCode", "Purchases",
]

let package = Package(
    name: "Features",
    defaultLocalization: "en",
    platforms: [.iOS(.v17)],
    products: [.library(name: "FeatureSupport", targets: ["FeatureSupport"])]
        + features.map { .library(name: "\($0)Feature", targets: ["\($0)Feature"]) },
    dependencies: [
        .package(path: "../Core"),
        .package(path: "../DesignSystem"),
        .package(path: "../Backend"),
        .package(path: "../Blocking"),
        .package(path: "../QRCode"),
        .package(path: "../Purchases"),
    ],
    targets: [
        .target(name: "FeatureSupport", dependencies: shared, path: "Sources/Support", resources: [.process("Resources")]),
        .target(
            name: "FeatureTestSupport",
            dependencies: shared + ["FeatureSupport", .product(name: "SnapshotSupport", package: "DesignSystem")],
            path: "Sources/TestSupport"
        ),
        .testTarget(name: "FeatureSupportTests", dependencies: ["FeatureSupport", "FeatureTestSupport"], path: "Tests/SupportTests"),
    ] + features.flatMap { name -> [Target] in
        [
            .target(
                name: "\(name)Feature",
                dependencies: shared + ["FeatureSupport"] + (featureDependencies[name] ?? []).map { .target(name: "\($0)Feature") },
                path: "Sources/\(name)",
                resources: [.process("Resources")]
            ),
            .testTarget(
                name: "\(name)FeatureTests",
                dependencies: [.target(name: "\(name)Feature"), "FeatureSupport", "FeatureTestSupport"],
                path: "Tests/\(name)Tests",
                exclude: ["__Snapshots__"]
            ),
        ]
    },
    swiftLanguageModes: [.v6]
)
