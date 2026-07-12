import SwiftData
import SwiftUI
import TidesPlatform

/// Sidebar list of saved locations with swipe-to-delete and an add button.
struct LocationListView: View {
    @Binding var selection: SavedLocation?
    @Environment(\.modelContext)
    private var modelContext
    @Query(sort: \SavedLocation.createdAt)
    private var locations: [SavedLocation]
    @State private var isAddingLocation = false

    var body: some View {
        Group {
            if locations.isEmpty {
                ContentUnavailableView {
                    Label("No Saved Locations", systemImage: "mappin.slash")
                } description: {
                    Text("Add a location from the map to see tide predictions.")
                } actions: {
                    Button("Add Location") {
                        isAddingLocation = true
                    }
                }
            } else {
                List(selection: $selection) {
                    ForEach(locations) { location in
                        NavigationLink(value: location) {
                            VStack(alignment: .leading) {
                                Text(location.name)
                                Text(coordinateText(for: location))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .onDelete(perform: delete)
                }
            }
        }
        .navigationTitle("Locations")
        .toolbar {
            ToolbarItem {
                Button("Add Location", systemImage: "plus") {
                    isAddingLocation = true
                }
            }
        }
        .sheet(isPresented: $isAddingLocation) {
            AddLocationView()
        }
    }

    private func coordinateText(for location: SavedLocation) -> String {
        String(
            format: "%.4f, %.4f",
            location.latitude,
            location.longitude
        )
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets {
            let location = locations[index]
            if selection == location {
                selection = nil
            }
            modelContext.delete(location)
        }
    }
}
