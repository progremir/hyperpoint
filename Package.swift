// swift-tools-version: 6.2
import PackageDescription

// One library with three folders and a thin app. Per-layer targets do not stop the app importing a lower layer
// (measured), so access control is the boundary and scripts/check-layers.sh guards layer purity inside the library.
let strict: [SwiftSetting] = [
    .swiftLanguageMode(.v6),
    .enableUpcomingFeature("ExistentialAny"),
    .enableUpcomingFeature("InternalImportsByDefault"),
    .treatAllWarnings(as: .error),
]

let package = Package(
    name: "Hyperpoint",
    platforms: [.macOS("27.0")],
    targets: [
        .target(name: "HyperpointKit", swiftSettings: strict),
        .executableTarget(name: "Hyperpoint", dependencies: ["HyperpointKit"], swiftSettings: strict),
        .testTarget(name: "HyperpointKitTests", dependencies: ["HyperpointKit"], swiftSettings: strict),
    ]
)
