// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Tides",
    defaultLocalization: "en",
    platforms: [
        .iOS(.v18),
        .macOS(.v15),
        .visionOS(.v2),
    ],
    products: [
        // Expose core and UI as libraries so an app target in Xcode can depend on them.
        .library(name: "TidesCore", targets: ["TidesCore"]),
        .library(name: "TidesPlatform", targets: ["TidesPlatform"]),
        .library(name: "TidesUI", targets: ["TidesUI"]),
    ],
    dependencies: [
        .package(url: "https://github.com/SimplyDanny/SwiftLintPlugins", exact: "0.59.0"),
        .package(url: "https://github.com/apple/swift-log.git", from: "1.5.0"),
    ],
    targets: [
        .target(
            name: "TidesCore",
            dependencies: [
                .product(name: "Logging", package: "swift-log")
            ],
            path: "Sources/Core",
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency"),
                .swiftLanguageMode(.v6),
            ]
        ),
        .target(
            name: "TidesPlatform",
            dependencies: [
                .target(name: "TidesCore"),
                .product(name: "Logging", package: "swift-log"),
            ],
            path: "Sources/Platform",
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency"),
                .swiftLanguageMode(.v6),
            ]
        ),
        .target(
            name: "TidesUI",
            dependencies: [
                .target(name: "TidesCore"),
                .target(name: "TidesPlatform"),
            ],
            path: "Sources/UI",
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency"),
                .swiftLanguageMode(.v6),
            ]
        ),
        .testTarget(
            name: "TidesCoreTests",
            dependencies: ["TidesCore"],
            path: "Tests/TidesCoreTests"
        ),
        .testTarget(
            name: "TidesUITests",
            dependencies: ["TidesUI", "TidesCore"],
            path: "Tests/TidesUITests"
        ),
    ]
)
