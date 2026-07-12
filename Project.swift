import ProjectDescription

let version = "1.0.0"
let copyright = "© 2024 Atsushi Nagase. All rights reserved."

let buildNumber = Environment.buildNumber.getString(default: "0")

let project = Project(
    name: "Tides",
    organizationName: "Atsushi Nagase",
    options: .options(
        defaultKnownRegions: ["en", "ja"],
        developmentRegion: "en"
    ),
    packages: [
        .package(path: ".")
    ],
    settings: .settings(
        base: [
            "INFOPLIST_KEY_LSApplicationCategoryType": .string("public.app-category.weather"),
            "INFOPLIST_KEY_CFBundleIconFile": .string("AppIcon"),
            "CURRENT_PROJECT_VERSION": .string(buildNumber),
            "MARKETING_VERSION": .string(version),
            "DEVELOPMENT_TEAM": .string("3Y8APYUG2G"),
            "SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD": "NO"
        ]),
    targets: [
        .target(
            name: "Tides",
            destinations: [.iPhone, .iPad, .mac, .appleVision],
            product: .app,
            bundleId: "io.ngs.Tides",
            deploymentTargets: .multiplatform(
                iOS: "18.0",
                macOS: "15.0",
                visionOS: "2.0"
            ),
            infoPlist: .extendingDefault(with: [
                "ITSAppUsesNonExemptEncryption": .boolean(false),
                "CFBundleVersion": .string("$(CURRENT_PROJECT_VERSION)"),
                "CFBundleShortVersionString": .string("$(MARKETING_VERSION)"),
                "NSHumanReadableCopyright": .string(copyright),
                "LSApplicationCategoryType": .string("public.app-category.weather"),
                "UILaunchScreen": [
                    "UIColorName": "AccentColor",
                    "UIImageRespectsSafeAreaInsets": true
                ],
                "API_HOST": .string("api.tides.ngs.io"),
                "NSLocationWhenInUseUsageDescription": .string(
                    "Your location is used to show nearby tide points on the map.")
            ]),
            sources: ["Sources/App/**"],
            // The entitlements file must not be copied into the bundle,
            // otherwise code signing fails on macOS.
            resources: [
                .glob(pattern: "Resources/**", excluding: ["Resources/Tides.entitlements"])
            ],
            entitlements: .file(path: "Resources/Tides.entitlements"),
            scripts: [
                .pre(
                    script: "${SRCROOT}/Scripts/swiftlint-fix-build-phase.sh",
                    name: "SwiftLint Auto-Fix",
                    basedOnDependencyAnalysis: false
                )
            ],
            dependencies: [
                .package(product: "TidesCore"),
                .package(product: "TidesPlatform"),
                .package(product: "TidesUI"),
                // The watch app is only embedded in the iOS build.
                .target(name: "TidesWatch", condition: .when([.ios]))
            ]
        ),
        // Apple Watch companion app.
        .target(
            name: "TidesWatch",
            destinations: [.appleWatch],
            product: .app,
            bundleId: "io.ngs.Tides.watchkitapp",
            deploymentTargets: .watchOS("11.0"),
            infoPlist: .extendingDefault(with: [
                "ITSAppUsesNonExemptEncryption": .boolean(false),
                "CFBundleVersion": .string("$(CURRENT_PROJECT_VERSION)"),
                "CFBundleShortVersionString": .string("$(MARKETING_VERSION)"),
                "NSHumanReadableCopyright": .string(copyright),
                "WKApplication": .boolean(true),
                "WKCompanionAppBundleIdentifier": .string("io.ngs.Tides")
            ]),
            sources: ["Sources/Watch/**"],
            resources: ["WatchResources/**"],
            dependencies: [
                .package(product: "TidesCore")
            ]
        ),
        .target(
            name: "TidesTests",
            destinations: [.iPhone, .iPad, .mac, .appleVision],
            product: .unitTests,
            bundleId: "io.ngs.TidesTests",
            deploymentTargets: .multiplatform(
                iOS: "18.0",
                macOS: "15.0",
                visionOS: "2.0"
            ),
            sources: ["Tests/TidesUITests/**"],
            dependencies: [
                .package(product: "TidesCore"),
                .package(product: "TidesPlatform"),
                .package(product: "TidesUI")
            ]
        )
    ],
    schemes: [
        .scheme(
            name: "Tides",
            buildAction: .buildAction(targets: ["Tides"]),
            testAction: .targets(
                ["TidesTests"],
                configuration: .debug,
                options: .options(coverage: true)
            ),
            runAction: .runAction(configuration: .debug)
        ),
        .scheme(
            name: "TidesWatch",
            buildAction: .buildAction(targets: ["TidesWatch"]),
            runAction: .runAction(configuration: .debug)
        )
    ]
)
