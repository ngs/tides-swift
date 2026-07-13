import ProjectDescription

let version = "1.0.0"
let copyright = "© 2024 Atsushi Nagase. All rights reserved."

let buildNumber = Environment.buildNumber.getString(default: "0")

/// Entitlements are code-signing inputs, never bundle resources.
let entitlementFiles: [Path] = [
    "Resources/Tides.entitlements",
    "Resources/Tides-iOS.entitlements",
    "Resources/TidesWidget.entitlements",
    "Resources/TidesWidget-macOS.entitlements",
    "Resources/TidesWatch.entitlements"
]

/// iOS-style entitlements (bare App Group identifier) also apply to visionOS;
/// macOS needs the Team ID prefix and keeps the base file.
let iOSEntitlementOverrides: SettingsDictionary = [
    "CODE_SIGN_ENTITLEMENTS[sdk=iphoneos*]": "Resources/Tides-iOS.entitlements",
    "CODE_SIGN_ENTITLEMENTS[sdk=iphonesimulator*]": "Resources/Tides-iOS.entitlements",
    "CODE_SIGN_ENTITLEMENTS[sdk=xros*]": "Resources/Tides-iOS.entitlements",
    "CODE_SIGN_ENTITLEMENTS[sdk=xrsimulator*]": "Resources/Tides-iOS.entitlements"
]

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
            // Development builds provision themselves; the release lanes switch
            // the Release configuration to the match profiles.
            "CODE_SIGN_STYLE": .string("Automatic"),
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
                // SwiftData + CloudKit is pushed changes from the other devices
                // as silent remote notifications.
                "UIBackgroundModes": .array([.string("remote-notification")]),
                "API_HOST": .string("api.tides.ngs.io"),
                "NSLocationWhenInUseUsageDescription": .string(
                    "Your location is used to show nearby tide points on the map.")
            ]),
            sources: ["Sources/App/**"],
            // Entitlements files must not be copied into the bundle, otherwise
            // code signing fails on macOS.
            resources: [
                .glob(pattern: "Resources/**", excluding: entitlementFiles)
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
                // The watch app is iOS-only; the widget is embedded in the
                // iOS and macOS builds.
                .target(name: "TidesWatch", condition: .when([.ios])),
                .target(name: "TidesWidget", condition: .when([.ios, .macos]))
            ],
            settings: .settings(base: iOSEntitlementOverrides)
        ),
        // Home screen / lock screen widget: current tide and next high and low
        // water for a saved location, computed offline from the shared store.
        .target(
            name: "TidesWidget",
            destinations: [.iPhone, .iPad, .mac],
            product: .appExtension,
            bundleId: "io.ngs.Tides.widget",
            deploymentTargets: .multiplatform(
                iOS: "18.0",
                macOS: "15.0"
            ),
            infoPlist: .extendingDefault(with: [
                "CFBundleDisplayName": .string("Tides"),
                "CFBundleVersion": .string("$(CURRENT_PROJECT_VERSION)"),
                "CFBundleShortVersionString": .string("$(MARKETING_VERSION)"),
                "NSExtension": .dictionary([
                    "NSExtensionPointIdentifier": .string("com.apple.widgetkit-extension")
                ])
            ]),
            sources: ["Sources/Widget/**"],
            resources: [
                .glob(pattern: "Resources/**", excluding: entitlementFiles)
            ],
            // macOS extensions must be sandboxed and use the Team ID-prefixed
            // App Group; iOS uses the bare identifier.
            entitlements: .file(path: "Resources/TidesWidget-macOS.entitlements"),
            dependencies: [
                .package(product: "TidesCore"),
                .package(product: "TidesPlatform")
            ],
            settings: .settings(
                base: [
                    "CODE_SIGN_ENTITLEMENTS[sdk=iphoneos*]":
                        "Resources/TidesWidget.entitlements",
                    "CODE_SIGN_ENTITLEMENTS[sdk=iphonesimulator*]":
                        "Resources/TidesWidget.entitlements"
                ]
            )
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
            // No App Group on the watch: it reads the saved locations from the
            // CloudKit-mirrored SwiftData store instead.
            entitlements: .file(path: "Resources/TidesWatch.entitlements"),
            dependencies: [
                .package(product: "TidesCore"),
                .package(product: "TidesPlatform")
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
