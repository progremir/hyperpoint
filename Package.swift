// swift-tools-version: 6.2
import PackageDescription

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
        .testTarget(name: "HyperpointTests", dependencies: ["Hyperpoint"], swiftSettings: strict),
    ]
)
