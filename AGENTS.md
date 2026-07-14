# AGENTS.md - Guide for AI coding assistants

> **Note**: This file (`AGENTS.md`) is the source of truth. `CLAUDE.md` is a symlink to it — always edit `AGENTS.md`.

## Overview

**Tides** — a tide prediction app for iPhone, iPad, Apple Watch, Vision Pro and macOS.

Pick a point on the map, download its harmonic constituent parameters once from tides-api (https://api.tides.ngs.io/), and every prediction from then on is computed locally, offline.

### Stack
- **Language**: Swift 6.0 (strict concurrency)
- **Frameworks**: SwiftUI, MapKit, Swift Charts, SwiftData
- **Deployment targets**: iOS 18.0 / macOS 15.0 / watchOS 11.0 / visionOS 2.0
- **Architecture**: MVVM over local SPM packages
- **Project generation**: Tuist (`Project.swift`) + Swift Package Manager (`Package.swift`)
- **Code quality**: SwiftLint / Periphery / RuboCop (for the Fastfile)
- **CI/CD**: GitHub Actions + fastlane
- **Localization**: String Catalogs (English is the development language, plus Japanese)

### Modules

The logic lives in three libraries of a local SPM package (`Package.swift`); the Tuist app targets depend on them.

| Module | Path | Contents |
|---|---|---|
| `TidesCore` | `Sources/Core/` | Harmonic engine (HarmonicParameters / NodalCorrection / TidePredictor), moon phase (MoonPhase), sunrise/sunset (SunCalculator), and the parameters API client. **Depends on Foundation only — no UI frameworks.** |
| `TidesPlatform` | `Sources/Platform/` | SwiftData persistence (SavedLocation), place search and reverse geocoding |
| `TidesUI` | `Sources/UI/` | SwiftUI views and view models |

| Tuist target | Product | Sources | Platforms |
|---|---|---|---|
| `Tides` | app | `Sources/App/` | iPhone / iPad / macOS / Vision Pro |
| `TidesWatch` | app | `Sources/Watch/` | watchOS (embedded in the iOS build) |
| `TidesWidget` | appExtension | `Sources/Widget/` | iOS / macOS (WidgetKit, embedded in each app build) |
| `TidesTests` | unitTests | `Tests/TidesUITests/` | iOS / macOS / visionOS |

App icons: `Resources/Assets.xcassets/AppIcon.appiconset` holds the iOS single-size icon and the full macOS set; visionOS uses the layered `AppIconVision.solidimagestack`, selected with `ASSETCATALOG_COMPILER_APPICON_NAME[sdk=xros*]` / `ASSETCATALOG_COMPILER_APPICON_NAME[sdk=xrsimulator*]`, and the watch app has its own set in `WatchResources`. The current artwork is a provisional CoreGraphics render (night sea, waves, full moon) awaiting a real design.

The app and the widget share a SwiftData store in an App Group (`TidesModelContainer`).
- **The App Group identifier differs by platform**: `group.io.ngs.Tides` on iOS / visionOS / watchOS, but macOS requires the team prefix, so it is `3Y8APYUG2G.group.io.ngs.Tides` (written as `$(TeamIdentifierPrefix)group.io.ngs.Tides`). It is one group in the portal.
- Entitlements: macOS uses `Resources/Tides.entitlements` (sandbox + team-prefixed group); iOS and visionOS use `Resources/Tides-iOS.entitlements`, selected with `CODE_SIGN_ENTITLEMENTS[sdk=iphone*|xr*]`. The widget has `TidesWidget-macOS.entitlements` (base) and `TidesWidget.entitlements` (iOS).
- Without the App Group entitlement the container falls back to a local store: the app still works, but the widget sees no data.

Saved locations (`SavedLocation`) sync across every platform through the CloudKit private database (`iCloud.io.ngs.Tides`, see `TidesCloudKit.containerIdentifier`).
- **CloudKit mirroring constraints**: every persisted property must be optional or have a default, and `@Attribute(.unique)` and relationships are not allowed. `Tests/TidesUITests/CloudKitSyncTests.swift` pins the schema against these rules.
- **Schema deployment**: TestFlight/App Store builds use the Production CloudKit environment, where record types are never auto-created — a model change shipped without a schema deploy breaks sync *silently* (the fallback ladder hides the error). `CloudKit/schema.ckdb` is the committed snapshot of the generated schema; after changing `SavedLocation`, run a Debug build once (this updates Development), then `Scripts/cloudkit-schema.sh export` and commit, then `Scripts/cloudkit-schema.sh deploy` (Production accepts additive changes only). The release workflow fails when Production drifts from the snapshot (`Scripts/cloudkit-schema.sh check`, `CLOUDKIT_MANAGEMENT_TOKEN` secret; cktool management tokens are issued in CloudKit Console → Settings → Tokens & Keys and expire).
- Fallback ladder (`TidesModelContainer.configurations(cloudKit:)`): CloudKit + App Group → CloudKit only (watch) → App Group only → local → in-memory. Missing entitlements, a device not signed into iCloud, previews and tests all drop to a configuration without CloudKit (`TidesCloudKit.isAvailable`).
- The watch app has no App Group; it reads the CloudKit-synced SwiftData store with `@Query` and lists the locations when there is more than one.
- Entitlements: every target carries `com.apple.developer.icloud-container-identifiers` and `icloud-services` (CloudKit); the app and the watch also carry `aps-environment` for push (`com.apple.developer.aps-environment` on macOS, `Resources/TidesWatch.entitlements` for the watch). The app's Info.plist declares `UIBackgroundModes: [remote-notification]`.
- `TidesPlatform`'s MapKit-backed types (`PlaceSearchService`, `ReverseGeocoder`) are excluded on watchOS with `#if !os(watchOS)`.

The datum preference syncs across devices through iCloud's key-value store: `TideDatumSync` (TidesCore) mirrors it with the App Group defaults suite, started once at launch by the app and the watch app. `@AppStorage` bindings and the widget keep reading the local suite unchanged. Requires the `com.apple.developer.ubiquity-kvstore-identifier` entitlement (`$(TeamIdentifierPrefix)io.ngs.Tides` on every app target — one shared store); the widget extension cannot use the key-value store and is deliberately left out.

SPM test targets: `Tests/TidesCoreTests/` (golden fixtures) and `Tests/TidesUITests/` (view models). Both run under `swift test`.

### TidesCore (the tide engine)
- A port of the Go implementation in tides-api (`internal/domain/tide.go`, `nodal.go`).
- Prediction: `h(t) = msl + Σ f_k(t)·A_k·cos(ω_k·Δt + V_k + u_k(t) − φ_k)`
  - Δt: hours since `referenceTime` (2012-01-01 UTC for FES)
  - V_k: the equilibrium argument at the reference epoch, served as `equilibrium_argument_deg` (a constant for the response)
  - f/u (nodal corrections): computed on the client from the astronomical arguments (Schureman) at the absolute prediction time
- **Golden fixtures**: `Tests/TidesCoreTests/Fixtures/*.json` are generated by the Go implementation and are the reference the Swift port must match (tolerances are recorded in the fixtures). Changing the Go formulas means regenerating them — see `tmp/fixturegen` in the tides-api repo.
- Heights default to the chart datum (Z0 = MSL − the M2 + S2 + K1 + O1 amplitudes), which is what Japanese tide tables use; mean sea level is selectable from the detail view's overflow menu.

### MoonPhase
- Moon age, illuminated fraction and the eight phases (SF Symbols `moonphase.*`) from the moon–sun elongation, using the principal terms of Meeus, *Astronomical Algorithms* (ch. 25 / 47). Foundation only.
- `Tests/TidesCoreTests/MoonPhaseTests.swift` checks it against observed new/full/quarter moon times (USNO / IMCCE).
- Moon age advances by 0.85–1.15 days per day — that variation is the orbital eccentricity, not a bug.

### SunCalculator
- Sunrise/sunset per civil day from the NOAA solar position algorithm (Meeus ch. 25); handles polar day/night (`SolarDay.alwaysUp` / `.alwaysDown`). Foundation only.
- The detail chart shades the night intervals so the fill reads as day vs night, and shows the displayed day's sunrise/sunset under the chart. The medium widget, the watch app and the calendar's selected-day detail list the times too.
- `Tests/TidesCoreTests/SunCalculatorTests.swift` pins the times against NAOJ (Tokyo) and NOAA (Sydney, Svalbard) references.

### API
- `GET /v1/tides/parameters?lat=&lon=` — harmonic parameters; this is the endpoint the app relies on
- `GET /v1/tides/predictions` — server-side predictions, useful for cross-checking
- The parameters response decodes directly into `HarmonicParameters` (Codable).
- The host comes from the `API_HOST` key in Info.plist (default `api.tides.ngs.io`).

## Commands

```bash
tuist generate --no-open   # generate the Xcode project and workspace
swift test                 # SPM tests, including the engine's fixture tests
xcodebuild test -workspace Tides.xcworkspace -scheme Tides \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
Scripts/lint.sh strict     # SwiftLint (CI runs --strict)
periphery scan --strict    # unused code
bundle exec rubocop        # Ruby (Fastfile and friends)
Scripts/screenshots.sh     # App Store screenshots, every platform and locale
```

## App Store screenshots

`Scripts/screenshots.sh` captures the whole set — iPhone, iPad, Mac, Vision Pro
and Watch, in seven locales — straight into `fastlane/screenshots/`, which is
where the `deliver_screenshots` lanes upload from. Nothing about it is manual,
and nothing about it depends on the machine it runs on.

```bash
git submodule update --init                  # first time: fetch the screenshots
Scripts/screenshots.sh                       # everything (~40 min)
Scripts/screenshots.sh --platform ios        # ios | mac | visionos | watchos
Scripts/screenshots.sh --locales en-US,ja    # a subset; --locales all for every one
bundle exec fastlane ios deliver_screenshots # then upload (also mac / visionos)
```

**`fastlane/screenshots` is a submodule** ([ngs/tides-screenshots]) — the images
are ~220 MB, most of it visionOS at 3840x2160, and they are rewritten wholesale
on every release; keeping them out of this history keeps a clone of the app
cheap. After a shoot, commit them there and then record the pointer here:

```bash
git -C fastlane/screenshots add -A && git -C fastlane/screenshots commit -m "…"
git -C fastlane/screenshots push origin main
git add fastlane/screenshots     # the parent records which shots go with this code
```

[ngs/tides-screenshots]: https://github.com/ngs/tides-screenshots

**Determinism.** The app is launched with an in-memory store seeded from
`Tests/Screenshots/Fixtures` (`ScreenshotSeed`) and its clock pinned to a fixed
instant (`TideClock`), so the same tide curve comes out of every run, offline,
with no iCloud account and no API call. The shots are taken on simulators the
script creates for itself (named `Shiomi Shot …`), because a simulator you have
developed on is signed into iCloud and interrupts the run with an Apple Account
prompt — with your email address in the frame.

**Sizes.** Simulator screenshots already come out at exactly the pixel sizes App
Store Connect demands (1320x2868 iPhone 6.9", 2064x2752 iPad 13", 3840x2160
Vision Pro, 416x496 Watch), so nothing is resized. `deliver` sorts the files into
store display types by pixel size, not by name — which is why the watch shots sit
in `screenshots/ios/` (the watch app is part of the iOS app) and why the visionOS
path must keep the word "vision" in it (3840x2160 is also an Apple TV size).

**The awkward platforms.** A UI test cannot photograph a visionOS screen at all
("Manual screenshots are not supported"), and on macOS it flattens the window —
black corners, no shadow. Both are captured from the host instead (`simctl io`
and `screencapture` respectively) while the test holds the app still; they
rendezvous through the work directory. The Mac window is then composed onto a
backdrop by `Scripts/compose_mac_screenshot.swift` — drop a
`fastlane/screenshots/mac/backdrop.png` to replace the default gradient. The
watch keeps the simulator's real clock: `simctl status_bar override` is rejected
on watchOS, so the 9:41 the other platforms show cannot be set there.

**fastlane must be 2.230.0 or newer.** Earlier versions reject the 6.9" iPhone,
13" iPad and Vision Pro sizes outright.

## Conventions
- Write commit messages in English, in the imperative. Never put an AI tool's name in a PR title.
- Write comments and documentation in English. This is a public repository.
- User-facing strings go through the String Catalogs (`Resources/Localizable.xcstrings`, and `WatchResources/Localizable.xcstrings` for the watch). Never hardcode them.
- `TidesCore` depends on Foundation only — no UI frameworks.
- SwiftLint, Periphery and RuboCop must all report zero violations; CI enforces this.
