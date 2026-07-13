import SwiftData
import SwiftUI
import TidesPlatform

/// Root split view: saved locations in the sidebar, tide detail on the right.
public struct ContentView: View {
    @Query(sort: [SortDescriptor(\SavedLocation.sortOrder), SortDescriptor(\SavedLocation.createdAt)])
    private var locations: [SavedLocation]
    @State private var selection: SavedLocation?
    /// Whether the launch-time selection restore already ran (or the user
    /// picked a location themselves), so late-arriving CloudKit data does
    /// not override an explicit deselection.
    @State private var hasRestoredSelection = false

    public init() {}

    public var body: some View {
        NavigationSplitView {
            LocationListView(selection: $selection)
                // Left to itself the sidebar opens narrow enough to hyphenate
                // the empty state's title mid-word ("No Saved Loca-tions"). The
                // floor is set by the longest word that cannot be broken across
                // the languages we ship: Greek's "αποθηκευμένες", with German's
                // "gespeicherten" close behind. CJK is not a constraint — it
                // wraps between characters.
                .navigationSplitViewColumnWidth(min: 240, ideal: 260)
        } detail: {
            if let location = selection {
                // Its own stack, so pushing the calendar gets a back button.
                NavigationStack {
                    LocationDetailView(location: location, selection: $selection)
                }
                .id(location.persistentModelID)
            } else {
                ContentUnavailableView(
                    "Select a Location",
                    systemImage: "water.waves",
                    description: Text("Choose a saved location, or add one from the map.")
                )
            }
        }
        .onAppear {
            restoreSelection()
        }
        .onChange(of: locations) { _, _ in
            // The store may fill in after launch (first CloudKit sync).
            restoreSelection()
        }
        .onChange(of: selectedCoordinate) { _, newValue in
            if newValue != nil {
                hasRestoredSelection = true
            }
            LastViewedLocation.save(newValue)
        }
    }

    /// The coordinate to remember. Tracked instead of the selection itself
    /// because moving the pin in Edit Location changes the coordinate without
    /// changing the selected object, and the coordinate is the restore key.
    private var selectedCoordinate: LastViewedLocation.Coordinate? {
        selection.map { LastViewedLocation.Coordinate(latitude: $0.latitude, longitude: $0.longitude) }
    }

    private func restoreSelection() {
        guard !hasRestoredSelection, selection == nil,
              let match = LastViewedLocation.match(in: locations) else { return }
        selection = match
        hasRestoredSelection = true
    }
}

/// Remembers the location whose detail was last shown, so a relaunch can
/// reopen it. `SavedLocation` cannot carry a unique identifier (CloudKit
/// forbids `@Attribute(.unique)`), so the coordinate is the key.
private enum LastViewedLocation {
    struct Coordinate: Equatable {
        var latitude: Double
        var longitude: Double
    }

    private static let latitudeKey = "lastViewedLocationLatitude"
    private static let longitudeKey = "lastViewedLocationLongitude"

    /// Degrees of slack allowed when matching a remembered coordinate against
    /// a saved one. A stored `Double` is not guaranteed to survive a round
    /// trip through SwiftData and CloudKit bit for bit, and an exact
    /// comparison would silently drop the restore. 1e-5° is about a metre —
    /// far below the spacing of any two locations a user would save, and far
    /// above any rounding a round trip can introduce.
    private static let coordinateTolerance = 1e-5

    static func save(_ coordinate: Coordinate?) {
        let defaults = UserDefaults.standard
        guard let coordinate else {
            defaults.removeObject(forKey: latitudeKey)
            defaults.removeObject(forKey: longitudeKey)
            return
        }
        defaults.set(coordinate.latitude, forKey: latitudeKey)
        defaults.set(coordinate.longitude, forKey: longitudeKey)
    }

    static func match(in locations: [SavedLocation]) -> SavedLocation? {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: latitudeKey) != nil,
              defaults.object(forKey: longitudeKey) != nil else { return nil }
        let latitude = defaults.double(forKey: latitudeKey)
        let longitude = defaults.double(forKey: longitudeKey)
        return locations.first {
            abs($0.latitude - latitude) < coordinateTolerance
                && abs($0.longitude - longitude) < coordinateTolerance
        }
    }
}
