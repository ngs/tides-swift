import Foundation

/// The app's notion of "now".
///
/// Everything that draws the present moment — the red *Now* rule on the chart,
/// the current tide read-out, the calendar's today highlight — reads the time
/// through here instead of calling `Date()` directly, so that a process can be
/// pinned to a fixed instant.
///
/// The only thing that pins it today is the App Store screenshot run
/// (`Scripts/screenshots.sh`), which needs every shot to be reproducible: a
/// chart photographed at an arbitrary moment would differ on every run, and the
/// tide curve would be cropped at whatever phase the tide happened to be in.
/// Tests can pin it the same way.
///
/// The override is read once, at first use, from the environment rather than
/// from `UserDefaults`, so that it cannot be set by anything but the process
/// that launched the app.
public enum TideClock {
    /// ISO 8601 instant (e.g. `2026-03-21T09:41:00Z`) that `now` reports when
    /// set in the environment. Absent — the normal case — `now` is the wall
    /// clock.
    public static let fixedDateEnvironmentKey = "TIDES_FIXED_DATE"

    /// The current time, or the pinned instant when one was injected.
    public static var now: Date { fixedDate ?? Date() }

    /// Whether a fixed instant was injected. Views that would otherwise animate
    /// or auto-refresh against the wall clock can use this to hold still.
    public static var isPinned: Bool { fixedDate != nil }

    /// Parsed once: the environment cannot change under a running process.
    private static let fixedDate: Date? = {
        guard let value = ProcessInfo.processInfo.environment[fixedDateEnvironmentKey],
              !value.isEmpty else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        if let date = formatter.date(from: value) {
            return date
        }
        // Accept fractional seconds too, rather than silently ignoring a date
        // that merely carries more precision than expected.
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value)
    }()
}
