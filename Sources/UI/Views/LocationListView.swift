import SwiftData
import SwiftUI
import TidesPlatform

/// Sidebar list of saved locations. Locations can be edited (renamed / moved)
/// or deleted from the swipe actions, the context menu (which also works on
/// macOS), or the edit mode on iOS.
struct LocationListView: View {
    @Binding var selection: SavedLocation?
    @Environment(\.modelContext)
    private var modelContext
    @Query(sort: \SavedLocation.createdAt)
    private var locations: [SavedLocation]
    @State private var isAddingLocation = false
    @State private var locationToEdit: SavedLocation?
    @State private var locationToDelete: SavedLocation?

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
                list
            }
        }
        .navigationTitle("Locations")
        .toolbar {
            #if os(iOS)
            ToolbarItem(placement: .topBarLeading) {
                EditButton()
            }
            #endif
            ToolbarItem {
                Button("Add Location", systemImage: "plus") {
                    isAddingLocation = true
                }
            }
        }
        .sheet(isPresented: $isAddingLocation) {
            AddLocationView()
        }
        .sheet(item: $locationToEdit) { location in
            EditLocationView(location: location)
        }
        .confirmationDialog(
            "Delete Location",
            isPresented: Binding(
                get: { locationToDelete != nil },
                set: { if !$0 { locationToDelete = nil } }
            ),
            titleVisibility: .visible,
            presenting: locationToDelete
        ) { location in
            Button("Delete", role: .destructive) {
                delete(location)
            }
            Button("Cancel", role: .cancel) {
                locationToDelete = nil
            }
        } message: { location in
            Text("\(location.name) and its offline tide data will be removed.")
        }
    }

    private var list: some View {
        List(selection: $selection) {
            ForEach(locations) { location in
                NavigationLink(value: location) {
                    row(for: location)
                }
                .swipeActions(edge: .trailing) {
                    Button("Delete", systemImage: "trash", role: .destructive) {
                        locationToDelete = location
                    }
                    Button("Edit", systemImage: "pencil") {
                        locationToEdit = location
                    }
                    .tint(.accentColor)
                }
                .contextMenu {
                    Button("Edit Location", systemImage: "pencil") {
                        locationToEdit = location
                    }
                    Button("Delete", systemImage: "trash", role: .destructive) {
                        locationToDelete = location
                    }
                }
            }
            .onDelete(perform: deleteAll)
        }
    }

    private func row(for location: SavedLocation) -> some View {
        VStack(alignment: .leading) {
            Text(location.name)
            Text(coordinateText(for: location))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func coordinateText(for location: SavedLocation) -> String {
        String(
            format: "%.4f, %.4f",
            location.latitude,
            location.longitude
        )
    }

    /// Edit-mode / swipe deletion, which passes indices rather than models.
    private func deleteAll(at offsets: IndexSet) {
        for index in offsets {
            delete(locations[index])
        }
    }

    private func delete(_ location: SavedLocation) {
        if selection == location {
            selection = nil
        }
        modelContext.delete(location)
        locationToDelete = nil
    }
}
