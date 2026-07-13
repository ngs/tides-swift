import TidesUI
import XCTest

/// Drives the app through the screens that go on the App Store and writes a PNG
/// per screen, in whichever language and on whichever device the run was told
/// to use.
///
/// This is not a test in the assertion sense — it is the capture half of
/// `Scripts/screenshots.sh`, which sets up the simulator, runs it once per
/// locale, and collects the files. It still fails loudly when a screen it
/// expects never appears, because a screenshot run that silently photographed
/// the wrong screen is worse than one that stops.
///
/// The app is launched with a seeded in-memory store and a pinned clock (see
/// `ScreenshotSeed` and `TideClock`), so the same tide curve comes out of every
/// run on every platform.
@MainActor
final class ScreenshotTests: XCTestCase {
    private var app: XCUIApplication!
    /// Where the PNGs are written, and how long to wait for a screen.
    private let timeout: TimeInterval = 30

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchEnvironment = ScreenshotEnvironment.appEnvironment
        app.launchArguments = ScreenshotEnvironment.appArguments
    }

    func testCaptureScreenshots() throws {
        app.launch()

        // The seeded store re-opens the location the app was last showing, so
        // the chart is on screen at launch with no navigation at all.
        let chart = app.descendants(matching: .any)[TideAccessibilityID.calendar]
        XCTAssertTrue(
            chart.waitForExistence(timeout: timeout),
            "The detail screen never appeared. Is the seed reaching the app?"
        )
        // Let the curve finish its first asynchronous computation.
        waitForIdle()
        try capture("01_chart")

        try captureCalendar()
        try captureLocationList()
        try captureSettings()
    }

    /// The month calendar, reached from the detail toolbar.
    private func captureCalendar() throws {
        let calendarButton = app.buttons[TideAccessibilityID.calendar]
        guard calendarButton.waitForExistence(timeout: timeout) else {
            XCTFail("The Calendar button is missing from the detail toolbar.")
            return
        }
        calendarButton.tap()
        waitForIdle()
        try capture("02_calendar")
        dismissSheet()
    }

    /// The saved-location list. On iPhone the split view is collapsed onto the
    /// detail screen, so the list is behind the back button; everywhere else it
    /// is the permanently visible sidebar and is already in the shot.
    private func captureLocationList() throws {
        let firstRow = app.descendants(matching: .any)[TideAccessibilityID.locationRow(0)]
        if !firstRow.isHittable {
            // Compact width: walk back up the navigation stack.
            let back = app.navigationBars.buttons.firstMatch
            if back.exists { back.tap() }
        }
        guard firstRow.waitForExistence(timeout: timeout) else {
            XCTFail("The location list never appeared.")
            return
        }
        waitForIdle()
        try capture("03_locations")
    }

    /// The settings screen. macOS puts it in the app menu (⌘,) rather than a
    /// toolbar button, so there it is opened with the keyboard shortcut.
    private func captureSettings() throws {
        #if os(macOS)
        app.typeKey(",", modifierFlags: .command)
        #else
        let settings = app.buttons[TideAccessibilityID.settings]
        guard settings.waitForExistence(timeout: timeout) else {
            XCTFail("The Settings button is missing from the sidebar toolbar.")
            return
        }
        settings.tap()
        #endif
        waitForIdle()
        try capture("04_settings")
    }

    // MARK: - Capture

    /// Writes one PNG of the whole screen — status bar included, which is what
    /// the App Store expects — under the name the delivery step will sort by.
    private func capture(_ name: String) throws {
        let directory = ScreenshotEnvironment.workDirectory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        if ScreenshotEnvironment.configuration.externalCapture == true {
            try captureFromHost(name, in: directory)
            return
        }

        let screenshot: XCUIScreenshot
        #if os(macOS)
        // There is no "screen" to speak of on a Mac: the store wants the app's
        // window, not the whole desktop with whatever else is open on it.
        screenshot = app.windows.firstMatch.screenshot()
        #else
        screenshot = XCUIScreen.main.screenshot()
        #endif

        let url = directory.appendingPathComponent("\(name).png")
        try screenshot.pngRepresentation.write(to: url)
        print("[screenshot] \(url.path)")

        // Also attach it, so a failed CI run still carries the evidence.
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// Hands the capture over to the script and waits for it to finish.
    ///
    /// The two processes rendezvous through the work directory, the one place a
    /// simulator and the host can both write: the test drops a request, the
    /// script takes the shot with `simctl` and drops the answer. The app is
    /// held still for as long as this takes, which is the whole point.
    private func captureFromHost(_ name: String, in directory: URL) throws {
        let request = directory.appendingPathComponent("capture-request-\(name)")
        let response = directory.appendingPathComponent("capture-done-\(name)")
        try? FileManager.default.removeItem(at: response)
        try Data().write(to: request)

        let deadline = Date().addingTimeInterval(timeout)
        while !FileManager.default.fileExists(atPath: response.path) {
            guard Date() < deadline else {
                XCTFail("The host never captured \(name). Is Scripts/screenshots.sh watching?")
                return
            }
            Thread.sleep(forTimeInterval: 0.25)
        }
        print("[screenshot] \(directory.appendingPathComponent("\(name).png").path)")
    }

    // MARK: - Helpers

    /// SwiftUI settles a beat after the animation ends; the chart additionally
    /// computes its curve off the main actor. Waiting on a state we cannot
    /// observe from here would be guesswork, so this simply gives the frame
    /// time to land.
    private func waitForIdle() {
        Thread.sleep(forTimeInterval: 1.5)
    }

    private func dismissSheet() {
        #if os(iOS) || os(visionOS)
        // The sheets are dismissed by their own Done/Close button on the
        // navigation bar; swiping down is unreliable in a test.
        let dismiss = app.navigationBars.buttons.firstMatch
        if dismiss.exists { dismiss.tap() }
        #else
        app.typeKey(XCUIKeyboardKey.escape, modifierFlags: [])
        #endif
    }
}
