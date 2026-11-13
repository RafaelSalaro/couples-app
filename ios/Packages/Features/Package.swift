// swift-tools-version: 6.0
import PackageDescription

// One library per feature. Module names carry a "Feature" suffix so they never
// collide with model types such as `Schedule` or `Settings`.
let features = [
    "Onboarding", "Pairing", "Home", "Unlock", "Minutes",
    "Challenges", "Kudos", "Reports", "Schedule", "Settings",
]

let shared: [Target.Dependency] = [
    "Core", "DesignSystem", "Backend", "Blocking", "QRCode", "Purchases",
]

let package = Package(
    name: "Features",
    defaultLocalization: "en",
    platforms: [.iOS(.v17)],
    products: features.map { .library(name: "\($0)Feature", targets: ["\($0)Feature"]) },
    dependencies: [
        .package(path: "../Core"),
        .package(path: "../DesignSystem"),
        .package(path: "../Backend"),
        .package(path: "../Blocking"),
        .package(path: "../QRCode"),
        .package(path: "../Purchases"),
    ],
    targets: features.flatMap { name -> [Target] in
        [
            .target(name: "\(name)Feature", dependencies: shared, path: "Sources/\(name)"),
            .testTarget(
                name: "\(name)FeatureTests",
                dependencies: [.target(name: "\(name)Feature")],
                path: "Tests/\(name)Tests"
            ),
        ]
    },
    swiftLanguageModes: [.v6]
)
