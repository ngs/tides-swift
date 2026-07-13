import Foundation

/// Accessibility identifiers for the controls the screenshot run has to drive.
///
/// The screenshot tests navigate the app in every language it ships in, so they
/// cannot look controls up by their label: "Calendar" is "カレンダー" one run
/// later. Identifiers are not localized, and unlike labels they are not read
/// out by VoiceOver, so naming them here costs the user nothing.
///
/// Only the controls the tests actually tap carry one. The rest of the UI is
/// reachable by label, and adding identifiers it does not need would just be
/// more to keep in sync.
public enum TideAccessibilityID {
    /// Sidebar: opens the map to add a location.
    public static let addLocation = "toolbar.addLocation"
    /// Sidebar: opens the settings sheet (not on macOS, which uses ⌘,).
    public static let settings = "toolbar.settings"
    /// Detail: opens the month calendar.
    public static let calendar = "toolbar.calendar"
    /// Detail: the overflow menu holding Edit, Delete and the datum picker.
    public static let locationOptions = "toolbar.locationOptions"

    /// A row in the sidebar, addressed by its position in the list.
    public static func locationRow(_ index: Int) -> String {
        "sidebar.locationRow.\(index)"
    }
}
