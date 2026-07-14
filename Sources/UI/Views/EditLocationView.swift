import MapKit
import SwiftUI
import TidesPlatform

/// Edits a saved location: rename it and/or move it to another coordinate.
/// Moving re-downloads the harmonic parameters for the new point.
///
/// The form fields carry their own labels, so they are never wrapped in a
/// `LabeledContent` (on macOS that renders the label twice), and the map lives
/// outside the form, where it cannot force the sheet wider than its frame.
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
        content
            .overlay {
                // Moving the pin re-downloads the parameters; that network
                // round trip deserves a visible, input-blocking indicator.
                // A rename-only save is instant and keeps just the small
                // spinner in the toolbar.
                if (viewModel.isSaving && viewModel.coordinateChanged) || viewModel.isRefreshing {
                    FetchingParametersOverlay()
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

    @ViewBuilder private var content: some View {
        #if os(macOS)
        // A sheet on macOS has no navigation bar: title and buttons are laid
        // out explicitly, so nothing overflows the sheet's frame.
        VStack(alignment: .leading, spacing: 0) {
            Text("Edit Location")
                .font(.headline)
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 12)

            form
                .frame(maxHeight: 300)
            map
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()
            HStack {
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                saveButton
                    .keyboardShortcut(.defaultAction)
            }
            .padding(16)
        }
        .frame(width: 460, height: 620)
        #else
        NavigationStack {
            VStack(spacing: 0) {
                // Cap the form at its content's height so the map, not the
                // form's trailing whitespace, absorbs the tall screen. With
                // oversized dynamic type the form scrolls within the cap.
                form
                    .frame(maxHeight: 380)
                map
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .navigationTitle("Edit Location")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    saveButton
                }
            }
        }
        #endif
    }

    // MARK: - Form

    private var form: some View {
        Form {
            Section("Name") {
                // The field's own label is the row label; wrapping it in a
                // LabeledContent would show the label twice on macOS.
                TextField("Location Name", text: $viewModel.name)
            }

            Section {
                TextField("Latitude", text: $viewModel.latitudeText)
                    .monospacedDigit()
                    #if os(iOS)
                    .keyboardType(.numbersAndPunctuation)
                    #endif
                TextField("Longitude", text: $viewModel.longitudeText)
                    .monospacedDigit()
                    #if os(iOS)
                    .keyboardType(.numbersAndPunctuation)
                    #endif
            } header: {
                Text("Coordinates")
            } footer: {
                footer
            }

            Section {
                LabeledContent("Fetched") {
                    Text(viewModel.location.fetchedAt, format: .dateTime)
                        .monospacedDigit()
                }
                refreshButton
            } header: {
                Text("Tide Parameters")
            } footer: {
                Text("Downloads the harmonic parameters for this location again, picking up any later improvement to the tidal model.")
                    .font(.caption)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }

    @ViewBuilder private var refreshButton: some View {
        Button {
            Task {
                await viewModel.refreshParameters()
            }
        } label: {
            HStack {
                Label("Refresh Parameters", systemImage: "arrow.clockwise")
                if viewModel.isRefreshing {
                    Spacer()
                    ProgressView()
                        .controlSize(.small)
                }
            }
        }
        .disabled(!viewModel.canRefreshParameters)
    }

    @ViewBuilder private var footer: some View {
        Group {
            if viewModel.enteredCoordinate == nil {
                Text("Enter a latitude between -90 and 90 and a longitude between -180 and 180.")
                    .foregroundStyle(.red)
            } else if viewModel.coordinateChanged {
                Text("New tide parameters will be downloaded for the new coordinates.")
            } else {
                Text("Tap the map to move this location.")
            }
        }
        .font(.caption)
        // Wrap instead of running past the sheet's edge.
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private var saveButton: some View {
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

    // MARK: - Map

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
            // Bottom-leading keeps the stack clear of the system map controls.
            .overlay(alignment: .bottomLeading) {
                zoomControls
                    .padding(10)
            }
        }
    }

    private var zoomControls: some View {
        VStack(spacing: 0) {
            // The frame and content shape live inside the button: outside,
            // only the glyph itself would be tappable and a near-miss would
            // fall through to the map and move the pin.
            Button {
                viewModel.zoomIn()
            } label: {
                Label("Zoom In", systemImage: "plus")
                    .frame(width: 30, height: 30)
                    .contentShape(Rectangle())
            }
            Divider()
                .frame(width: 30)
            Button {
                viewModel.zoomOut()
            } label: {
                Label("Zoom Out", systemImage: "minus")
                    .frame(width: 30, height: 30)
                    .contentShape(Rectangle())
            }
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.plain)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .shadow(radius: 2)
    }
}
