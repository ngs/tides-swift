import MapKit
import SwiftData
import SwiftUI
import TidesPlatform

/// Location picker: search by name or address, or tap the map. Zoom controls
/// and an automatic zoom on selection make it possible to place the point
/// precisely instead of somewhere in a whole region.
struct AddLocationView: View {
    @Environment(\.dismiss)
    private var dismiss
    @Environment(\.modelContext)
    private var modelContext
    @State private var viewModel = AddLocationViewModel()
    @State private var cameraPosition: MapCameraPosition = .automatic

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                searchBar
                mapView
                controlPanel
            }
            .navigationTitle("Add Location")
            #if os(iOS) || os(visionOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .alert(
                "Error",
                isPresented: Binding(
                    get: { viewModel.errorMessage != nil },
                    set: { if !$0 { viewModel.errorMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
        }
        #if os(macOS)
        .frame(minWidth: 520, minHeight: 620)
        #endif
    }

    // MARK: - Search

    @ViewBuilder private var searchBar: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search for a place or address", text: $viewModel.searchQuery)
                    .textFieldStyle(.plain)
                    .onSubmit {
                        Task { await viewModel.search() }
                    }
                    #if os(iOS)
                    .submitLabel(.search)
                    .autocorrectionDisabled()
                    #endif
                if viewModel.isSearching {
                    ProgressView()
                        .controlSize(.small)
                } else if !viewModel.searchQuery.isEmpty {
                    Button("Clear Search", systemImage: "xmark.circle.fill") {
                        viewModel.clearSearch()
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
                Button("Search") {
                    Task { await viewModel.search() }
                }
                .disabled(viewModel.searchQuery.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)

            if !viewModel.searchResults.isEmpty {
                searchResultList
            }
            Divider()
        }
    }

    private var searchResultList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(viewModel.searchResults) { suggestion in
                    Button {
                        viewModel.select(suggestion: suggestion)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(suggestion.name)
                            if !suggestion.subtitle.isEmpty {
                                Text(suggestion.subtitle)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                        .padding(.vertical, 6)
                        .padding(.horizontal)
                    }
                    .buttonStyle(.plain)
                    Divider()
                }
            }
        }
        .frame(maxHeight: 180)
    }

    // MARK: - Map

    private var mapView: some View {
        MapReader { proxy in
            Map(position: $cameraPosition) {
                if let coordinate = viewModel.selectedCoordinate {
                    Marker("Selected Point", systemImage: "water.waves", coordinate: coordinate)
                }
                UserAnnotation()
            }
            .mapControls {
                MapUserLocationButton()
                MapCompass()
                MapScaleView()
            }
            .onTapGesture { point in
                guard let coordinate = proxy.convert(point, from: .local) else { return }
                viewModel.select(coordinate: coordinate)
            }
            .onMapCameraChange(frequency: .onEnd) { context in
                viewModel.mapCameraChanged(to: context.region)
            }
            .onChange(of: viewModel.pendingCamera) { _, target in
                guard let target else { return }
                withAnimation {
                    cameraPosition = .region(target.region)
                }
                viewModel.consumePendingCamera()
            }
            .overlay(alignment: .topTrailing) {
                zoomControls
                    .padding(8)
            }
        }
    }

    private var zoomControls: some View {
        VStack(spacing: 0) {
            Button("Zoom In", systemImage: "plus") {
                viewModel.zoomIn()
            }
            Divider().frame(width: 28)
            Button("Zoom Out", systemImage: "minus") {
                viewModel.zoomOut()
            }
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.plain)
        .padding(6)
        .frame(width: 32)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .shadow(radius: 1)
    }

    // MARK: - Controls

    @ViewBuilder private var controlPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            switch viewModel.phase {
            case .selecting, .fetching:
                if let coordinate = viewModel.selectedCoordinate {
                    Text(String(format: "%.4f, %.4f", coordinate.latitude, coordinate.longitude))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                } else {
                    Text("Search for a place, or tap the map to select a location.")
                        .foregroundStyle(.secondary)
                }
                Button {
                    Task { await viewModel.fetchParameters() }
                } label: {
                    if viewModel.phase == .fetching {
                        HStack {
                            ProgressView()
                            Text("Fetching parameters…")
                        }
                        .frame(maxWidth: .infinity)
                    } else {
                        Text("Fetch Parameters for This Location")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!viewModel.canFetch)

            case .naming:
                Label("Available Offline", systemImage: "checkmark.icloud")
                    .font(.callout)
                    .foregroundStyle(.green)
                TextField("Location Name", text: $viewModel.locationName)
                    .textFieldStyle(.roundedBorder)
                Button {
                    save()
                } label: {
                    Text("Save")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!viewModel.canSave)
            }
        }
        .padding()
    }

    private func save() {
        guard let location = viewModel.makeSavedLocation() else { return }
        modelContext.insert(location)
        dismiss()
    }
}
