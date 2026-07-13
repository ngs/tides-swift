// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Tides",
    defaultLocalization: "en",
    platforms: [
        .iOS(.v18),
        .macOS(.v15),
        .watchOS(.v11),
        .visionOS(.v2),
    ],
    products: [
        // Expose core and UI as libraries so an app target in Xcode can depend on them.
        // Static so Xcode never embeds them as (separately signed) dynamic
        // frameworks in the app bundles.
        .library(name: "TidesCore", type: .static, targets: ["TidesCore"]),
        .library(name: "TidesPlatform", type: .static, targets: ["TidesPlatform"]),
        .library(name: "TidesUI", type: .static, targets: ["TidesUI"]),
    ],
    targets: [
        // Offline harmonic tide engine + parameters API client (Foundation only).
        .target(
            name: "TidesCore",
            path: "Sources/Core",
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency"),
                .swiftLanguageMode(.v6),
            ]
        ),
        // Persistence (SwiftData) and platform services (reverse geocoding).
        .target(
            name: "TidesPlatform",
            dependencies: [
                .target(name: "TidesCore")
            ],
            path: "Sources/Platform",
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency"),
                .swiftLanguageMode(.v6),
            ]
        ),
        // SwiftUI views and view models.
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
        // Golden fixture tests validating the Swift port against the Go
        // implementation in tides-api.
        .testTarget(
            name: "TidesCoreTests",
            dependencies: ["TidesCore"],
            path: "Tests/TidesCoreTests",
            resources: [
                .copy("Fixtures")
            ]
        ),
        .testTarget(
            name: "TidesUITests",
            dependencies: ["TidesUI", "TidesPlatform", "TidesCore"],
            path: "Tests/TidesUITests"
        ),
    ]
)
