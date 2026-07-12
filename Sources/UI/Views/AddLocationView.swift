import MapKit
import SwiftData
import SwiftUI
import TidesPlatform

/// Location picker: search by name or address, or tap the map.
///
/// The map fills the sheet; the search field and the action panel float above
/// it as safe area insets, so the map never gets squeezed and the layout does
/// not jump when the flow changes phase.
struct AddLocationView: View {
    @Environment(\.dismiss)
    private var dismiss
    @Environment(\.modelContext)
    private var modelContext
    @State private var viewModel = AddLocationViewModel()
    @State private var cameraPosition: MapCameraPosition = .automatic

    var body: some View {
        container
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

    /// A sheet on macOS has no navigation bar, so the title and the Cancel
    /// button are laid out explicitly instead of leaving an empty bar's worth
    /// of space at the top.
    @ViewBuilder private var container: some View {
        #if os(macOS)
        VStack(spacing: 0) {
            HStack {
                Text("Add Location")
                    .font(.headline)
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            Divider()
            picker
        }
        .frame(width: 560, height: 640)
        #else
        NavigationStack {
            picker
                .navigationTitle("Add Location")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            dismiss()
                        }
                    }
                }
        }
        #endif
    }

    private var picker: some View {
        mapView
            .safeAreaInset(edge: .top, spacing: 0) {
                searchField
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                controlPanel
            }
            .overlay(alignment: .top) {
                // Results float over the map instead of pushing it around.
                if !viewModel.searchResults.isEmpty {
                    searchResultList
                        .padding(.horizontal, 12)
                }
            }
    }

    // MARK: - Search

    private var searchField: some View {
        HStack(spacing: 8) {
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
                .textInputAutocapitalization(.never)
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
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.regularMaterial)
        .overlay(alignment: .bottom) {
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
                                .lineLimit(1)
                            if !suggestion.subtitle.isEmpty {
                                Text(suggestion.subtitle)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                        .padding(.vertical, 8)
                        .padding(.horizontal, 12)
                    }
                    .buttonStyle(.plain)

                    if suggestion.id != viewModel.searchResults.last?.id {
                        Divider()
                    }
                }
            }
        }
        .frame(maxHeight: 220)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .shadow(radius: 8, y: 2)
        .padding(.top, 8)
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
            // Bottom-leading keeps the zoom stack clear of the system map
            // controls (compass, user location, scale), which sit top-trailing.
            .overlay(alignment: .bottomLeading) {
                zoomControls
                    .padding(12)
            }
        }
    }

    private var zoomControls: some View {
        VStack(spacing: 0) {
            Button("Zoom In", systemImage: "plus") {
                viewModel.zoomIn()
            }
            .frame(width: 32, height: 32)
            Divider()
                .frame(width: 32)
            Button("Zoom Out", systemImage: "minus") {
                viewModel.zoomOut()
            }
            .frame(width: 32, height: 32)
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.plain)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .shadow(radius: 2)
    }

    // MARK: - Action panel

    private var controlPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider()
            coordinateSummary

            if viewModel.phase == .naming {
                TextField("Location Name", text: $viewModel.locationName)
                    .textFieldStyle(.roundedBorder)
            }

            primaryButton
                // A fixed height keeps the panel from resizing between phases.
                .frame(height: 32)
        }
        .padding(.horizontal, 12)
        .padding(.top, 4)
        .padding(.bottom, 12)
        .background(.regularMaterial)
    }

    @ViewBuilder private var coordinateSummary: some View {
        if let coordinate = viewModel.selectedCoordinate {
            HStack(spacing: 6) {
                if viewModel.phase == .naming {
                    Label("Available Offline", systemImage: "checkmark.icloud")
                        .foregroundStyle(.green)
                } else {
                    Image(systemName: "mappin.and.ellipse")
                        .foregroundStyle(.secondary)
                }
                Text(String(format: "%.4f, %.4f", coordinate.latitude, coordinate.longitude))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .font(.caption)
            .lineLimit(1)
        } else {
            Text("Search for a place, or tap the map to select a location.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    @ViewBuilder private var primaryButton: some View {
        switch viewModel.phase {
        case .selecting, .fetching:
            Button {
                Task { await viewModel.fetchParameters() }
            } label: {
                Group {
                    if viewModel.phase == .fetching {
                        HStack(spacing: 6) {
                            ProgressView()
                                .controlSize(.small)
                            Text("Fetching parameters…")
                        }
                    } else {
                        Text("Fetch Parameters for This Location")
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!viewModel.canFetch)

        case .naming:
            Button {
                save()
            } label: {
                Text("Save")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!viewModel.canSave)
        }
    }

    private func save() {
        guard let location = viewModel.makeSavedLocation() else { return }
        modelContext.insert(location)
        dismiss()
    }
}
