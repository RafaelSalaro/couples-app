// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Backend",
    defaultLocalization: "en",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "Backend", targets: ["Backend"]),
    ],
    dependencies: [
        .package(path: "../Core"),
        .package(url: "https://github.com/supabase/supabase-swift.git", from: "2.0.0"),
    ],
    targets: [
        .target(name: "Backend", dependencies: [
            "Core",
            .product(name: "Supabase", package: "supabase-swift"),
        ]),
        .testTarget(name: "BackendTests", dependencies: ["Backend"]),
    ],
    swiftLanguageModes: [.v6]
)
