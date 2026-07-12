import MapKit
import SwiftData
import SwiftUI
import TidesPlatform

/// Map-based location picker: tap to drop a pin, download the harmonic
/// parameters for that point, name it and save.
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
        .frame(minWidth: 480, minHeight: 520)
        #endif
    }

    private var mapView: some View {
        MapReader { proxy in
            Map(position: $cameraPosition) {
                if let coordinate = viewModel.selectedCoordinate {
                    Marker("Selected Point", systemImage: "water.waves", coordinate: coordinate)
                }
            }
            .onTapGesture { point in
                guard let coordinate = proxy.convert(point, from: .local) else { return }
                viewModel.select(coordinate: coordinate)
            }
        }
    }

    @ViewBuilder private var controlPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            switch viewModel.phase {
            case .selecting, .fetching:
                if let coordinate = viewModel.selectedCoordinate {
                    Text(String(format: "%.4f, %.4f", coordinate.latitude, coordinate.longitude))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                } else {
                    Text("Tap the map to select a location.")
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
