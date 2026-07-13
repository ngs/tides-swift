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
        .onChange(of: selection) { _, newValue in
            if newValue != nil {
                hasRestoredSelection = true
            }
            LastViewedLocation.save(newValue)
        }
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
    private static let latitudeKey = "lastViewedLocationLatitude"
    private static let longitudeKey = "lastViewedLocationLongitude"

    static func save(_ location: SavedLocation?) {
        let defaults = UserDefaults.standard
        guard let location else {
            defaults.removeObject(forKey: latitudeKey)
            defaults.removeObject(forKey: longitudeKey)
            return
        }
        defaults.set(location.latitude, forKey: latitudeKey)
        defaults.set(location.longitude, forKey: longitudeKey)
    }

    static func match(in locations: [SavedLocation]) -> SavedLocation? {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: latitudeKey) != nil,
              defaults.object(forKey: longitudeKey) != nil else { return nil }
        let latitude = defaults.double(forKey: latitudeKey)
        let longitude = defaults.double(forKey: longitudeKey)
        return locations.first {
            $0.latitude == latitude && $0.longitude == longitude
        }
    }
}
