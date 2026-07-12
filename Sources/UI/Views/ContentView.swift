import SwiftData
import SwiftUI
import TidesPlatform

/// Root split view: saved locations in the sidebar, tide detail on the right.
public struct ContentView: View {
    @State private var selection: SavedLocation?

    public init() {}

    public var body: some View {
        NavigationSplitView {
            LocationListView(selection: $selection)
        } detail: {
            if let location = selection {
                LocationDetailView(location: location, selection: $selection)
                    .id(location.persistentModelID)
            } else {
                ContentUnavailableView(
                    "Select a Location",
                    systemImage: "water.waves",
                    description: Text("Choose a saved location, or add one from the map.")
                )
            }
        }
    }
}
