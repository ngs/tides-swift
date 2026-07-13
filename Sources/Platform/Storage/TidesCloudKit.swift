import Foundation

/// CloudKit settings shared by every target.
///
/// The saved locations are mirrored to the user's private CloudKit database so
/// the iPhone, iPad, Mac, Vision Pro and Watch apps all see the same list. The
/// container is registered in the developer portal and listed in each target's
/// entitlements; the identifier lives here so it is written down exactly once.
public enum TidesCloudKit {
    /// Private CloudKit database backing the SwiftData store.
    public static let containerIdentifier = "iCloud.io.ngs.Tides"

    /// Environment variable that turns mirroring off, for tests and for
    /// debugging against a purely local store.
    public static let disableEnvironmentKey = "TIDES_DISABLE_CLOUDKIT"

    /// Whether this process should even try to open a CloudKit-backed store.
    ///
    /// Mirroring needs the iCloud entitlement *and* a signed-in iCloud account.
    /// Unit tests, SwiftUI previews and unsigned builds have neither, so they
    /// go straight to the local store instead of paying for a store that would
    /// fail to open. `TidesModelContainer` still falls back when this guess is
    /// too optimistic (entitlement present, account signed out mid-flight…),
    /// so a wrong answer here only costs a retry, never a crash.
    public static var isAvailable: Bool {
        let environment = ProcessInfo.processInfo.environment
        if environment[disableEnvironmentKey] != nil {
            return false
        }
        if isRunningTests || isRunningPreviews {
            return false
        }
        return FileManager.default.ubiquityIdentityToken != nil
    }

    /// True inside a test process, whether it is hosted by XCTest (the Xcode
    /// test targets) or is a bare swift-testing bundle run by `swift test`.
    private static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            || NSClassFromString("XCTestCase") != nil
            || Bundle.main.bundlePath.contains(".xctest")
            || ProcessInfo.processInfo.arguments.contains { $0.contains(".xctest") }
    }

    /// True inside an Xcode preview process.
    private static var isRunningPreviews: Bool {
        ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
    }
}
