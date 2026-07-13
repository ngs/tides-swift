import Foundation
import TidesCore
import TidesPlatform

/// How `Scripts/screenshots.sh` talks to the capture test.
///
/// The script owns everything variable about a run — which locale, which
/// instant, which locations, where the files land — and hands it over in a
/// `config.json` it drops in the *work directory* before starting the run. The
/// test reads it there and writes the PNGs back beside it.
///
/// A file rather than environment variables, because there is no dependable way
/// to get a variable from `xcodebuild` into a UI test *runner*: `TEST_RUNNER_…`
/// reaches the build, not the runner process (verified on Xcode 26). A
/// directory both sides can see is the one channel that behaves the same on a
/// simulator and on the Mac.
enum ScreenshotEnvironment {
    /// What the script asks for. Mirrored by the `config.json` it writes.
    struct Configuration: Decodable {
        /// Language to render the app in, e.g. `ja`, `zh-Hans`.
        var language: String
        /// Region for the formatters, e.g. `JP`. Without it a Japanese UI would
        /// draw US date formats.
        var region: String
        /// The seeded store, base64 of a `ScreenshotSeed.Payload` document.
        var seed: String
        /// ISO 8601 instant the app's clock is pinned to.
        var fixedDate: String
        /// Coordinate of the location the app should open on.
        var selectedLatitude: Double
        var selectedLongitude: Double
        /// Whether the host takes the picture instead of the test.
        ///
        /// visionOS refuses to screenshot from a UI test ("Manual screenshots
        /// are not supported"), so there the test only navigates and then asks
        /// the script — which can still use `simctl io … screenshot` — to
        /// capture the frame. Absent on every other platform, where the test
        /// takes its own.
        var externalCapture: Bool?
    }

    /// The directory shared with the script: `config.json` in, PNGs out.
    ///
    /// On a simulator the test cannot reach the host's filesystem, but the
    /// device's own data container is a plain directory on the host — which is
    /// how the script both delivers the config and collects the results. On
    /// macOS the test is a host process already, so a fixed cache directory
    /// serves the same purpose.
    static let workDirectory: URL = {
        let name = "io.ngs.Tides.screenshots"
        if let shared = ProcessInfo.processInfo.environment["SIMULATOR_SHARED_RESOURCES_DIRECTORY"] {
            return URL(fileURLWithPath: shared)
                .appendingPathComponent("Library/Caches")
                .appendingPathComponent(name)
        }
        return URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Caches")
            .appendingPathComponent(name)
    }()

    /// The run's configuration, or a failure loud enough to stop the run: a
    /// screenshot session that quietly fell back to defaults would photograph
    /// the wrong language in silence.
    static let configuration: Configuration = {
        let url = workDirectory.appendingPathComponent("config.json")
        guard let data = try? Data(contentsOf: url) else {
            fatalError("No screenshot config at \(url.path). Run Scripts/screenshots.sh, not the scheme.")
        }
        do {
            return try JSONDecoder().decode(Configuration.self, from: data)
        } catch {
            fatalError("Malformed screenshot config at \(url.path): \(error)")
        }
    }()

    /// Environment handed to the app under test: the seeded store, the pinned
    /// clock, and no CloudKit — a screenshot must not depend on what happens to
    /// be in the developer's (or the CI runner's) iCloud account.
    static var appEnvironment: [String: String] {
        [
            TidesCloudKit.disableEnvironmentKey: "1",
            ScreenshotSeed.environmentKey: configuration.seed,
            TideClock.fixedDateEnvironmentKey: configuration.fixedDate
        ]
    }

    /// Launch arguments for the app: the language to render in, and the
    /// location to reopen.
    ///
    /// `-AppleLanguages` / `-AppleLocale` are read by Foundation at startup and
    /// are the supported way to run a build in another language. The
    /// `lastViewedLocation…` pair lands in `UserDefaults`' argument domain,
    /// which is exactly where `ContentView` looks to restore its selection — so
    /// the app opens on the chart, with no code in the app aware of any of this.
    static var appArguments: [String] {
        let configuration = configuration
        let locale = configuration.language.replacingOccurrences(of: "-", with: "_")
        var arguments = [
            "-AppleLanguages", "(\(configuration.language))",
            "-AppleLocale", "\(locale)_\(configuration.region)",
            "-lastViewedLocationLatitude", String(configuration.selectedLatitude),
            "-lastViewedLocationLongitude", String(configuration.selectedLongitude)
        ]
        #if os(macOS)
        // Otherwise AppKit restores whatever window frame this Mac last used,
        // and the shot comes out at some arbitrary size instead of the app's
        // 16:10 default.
        arguments += ["-ApplePersistenceIgnoreState", "YES"]
        #endif
        return arguments
    }
}
