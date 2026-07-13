import XCTest

/// The watch half of the App Store screenshot run.
///
/// A separate test from `ScreenshotTests` because the watch app is a separate
/// app with its own UI — a list of the locations synced from the phone, and the
/// tide for the one you pick — and none of the phone's navigation applies. It
/// reads the same `config.json` and writes into the same work directory, so
/// `Scripts/screenshots.sh` collects it exactly like the rest.
@MainActor
final class WatchScreenshotTests: XCTestCase {
    private var app: XCUIApplication!
    private let timeout: TimeInterval = 30

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchEnvironment = ScreenshotEnvironment.appEnvironment
        app.launchArguments = ScreenshotEnvironment.appArguments
    }

    func testCaptureScreenshots() throws {
        app.launch()

        // Several locations are seeded, so the watch opens on its list.
        let firstLocation = app.buttons.firstMatch
        XCTAssertTrue(
            firstLocation.waitForExistence(timeout: timeout),
            "The watch never listed the seeded locations."
        )
        waitForIdle()
        try capture("01_locations")

        firstLocation.tap()
        waitForIdle()
        try capture("02_tide")
    }

    private func capture(_ name: String) throws {
        let screenshot = XCUIScreen.main.screenshot()
        let directory = ScreenshotEnvironment.workDirectory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("\(name).png")
        try screenshot.pngRepresentation.write(to: url)
        print("[screenshot] \(url.path)")

        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// The tide list computes its extrema when it appears; give it the frame.
    private func waitForIdle() {
        Thread.sleep(forTimeInterval: 1.5)
    }
}
