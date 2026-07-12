import MapKit
import SwiftUI
import TidesPlatform

/// Edits a saved location: rename it and/or move it to another coordinate.
/// Moving re-downloads the harmonic parameters for the new point.
struct EditLocationView: View {
    @Environment(\.dismiss)
    private var dismiss
    @State private var viewModel: EditLocationViewModel
    @State private var cameraPosition: MapCameraPosition

    init(location: SavedLocation) {
        let viewModel = EditLocationViewModel(location: location)
        _viewModel = State(initialValue: viewModel)
        _cameraPosition = State(initialValue: .region(viewModel.region))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("Location Name", text: $viewModel.name)
                }

                Section {
                    LabeledContent("Latitude") {
                        TextField("Latitude", text: $viewModel.latitudeText)
                            .multilineTextAlignment(.trailing)
                            .monospacedDigit()
                            #if os(iOS)
                            .keyboardType(.numbersAndPunctuation)
                            #endif
                    }
                    LabeledContent("Longitude") {
                        TextField("Longitude", text: $viewModel.longitudeText)
                            .multilineTextAlignment(.trailing)
                            .monospacedDigit()
                            #if os(iOS)
                            .keyboardType(.numbersAndPunctuation)
                            #endif
                    }
                    map
                        .frame(height: 220)
                        .listRowInsets(EdgeInsets())
                } header: {
                    Text("Coordinates")
                } footer: {
                    if viewModel.enteredCoordinate == nil {
                        Text("Enter a latitude between -90 and 90 and a longitude between -180 and 180.")
                            .foregroundStyle(.red)
                    } else if viewModel.coordinateChanged {
                        Text("New tide parameters will be downloaded for the new coordinates.")
                    } else {
                        Text("Tap the map to move this location.")
                    }
                }
            }
            #if os(iOS)
            .formStyle(.grouped)
            #endif
            .navigationTitle("Edit Location")
            #if os(iOS) || os(visionOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if viewModel.isSaving {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Button("Save") {
                            Task {
                                if await viewModel.save() {
                                    dismiss()
                                }
                            }
                        }
                        .disabled(!viewModel.canSave)
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
        .frame(minWidth: 460, minHeight: 560)
        #endif
    }

    private var map: some View {
        MapReader { proxy in
            Map(position: $cameraPosition) {
                if let coordinate = viewModel.enteredCoordinate {
                    Marker("Selected Point", systemImage: "water.waves", coordinate: coordinate)
                }
            }
            .onTapGesture { point in
                guard let coordinate = proxy.convert(point, from: .local) else { return }
                viewModel.select(coordinate: coordinate)
            }
        }
    }
}
