import Charts
import SwiftData
import SwiftUI
import TidesCore
import TidesPlatform

/// Tide detail screen: two-day tide curve, current level, high/low water list
/// and day navigation. Works fully offline from the saved parameters, and lets
/// the location be renamed, moved or deleted.
struct LocationDetailView: View {
    let location: SavedLocation
    /// Cleared by the parent when this location is deleted.
    @Binding var selection: SavedLocation?

    var body: some View {
        if let parameters = location.parameters {
            LocationDetailContentView(
                location: location,
                parameters: parameters,
                selection: $selection
            )
        } else {
            ContentUnavailableView(
                "Tide Data Unavailable",
                systemImage: "exclamationmark.triangle",
                description: Text("The saved parameters for this location could not be read.")
            )
        }
    }
}

private struct LocationDetailContentView: View {
    let location: SavedLocation
    @Binding var selection: SavedLocation?
    @Environment(\.modelContext)
    private var modelContext
    @AppStorage(TideDatumSettings.storageKey, store: TideDatumSettings.defaults)
    private var datum: TideDatum = TideDatumSettings.defaultDatum
    @State private var viewModel: LocationDetailViewModel
    @State private var isEditing = false
    @State private var isConfirmingDelete = false

    init(
        location: SavedLocation,
        parameters: HarmonicParameters,
        selection: Binding<SavedLocation?>
    ) {
        self.location = location
        _selection = selection
        _viewModel = State(initialValue: LocationDetailViewModel(
            parameters: parameters,
            latitude: location.latitude,
            longitude: location.longitude
        ))
    }

    var body: some View {
        List {
            Section {
                currentTideRow
            } header: {
                Text("Current Tide")
            } footer: {
                Label("Available Offline", systemImage: "checkmark.icloud")
                    .font(.caption)
            }

            Section {
                dayNavigator
                chart
                    .frame(minHeight: 220)
                    .padding(.vertical, 8)
                sunTimesRow
            } header: {
                Text("Tide Chart")
            }

            Section("High and Low Tides") {
                if viewModel.extrema.isEmpty {
                    Text("No high or low tides in this period.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(viewModel.extrema) { extremum in
                        extremumRow(extremum)
                    }
                }
            }

            Section {
                LabeledContent("Coordinates") {
                    Text(String(format: "%.4f, %.4f", location.latitude, location.longitude))
                        .monospacedDigit()
                }
                LabeledContent("Datum") {
                    Text(viewModel.datum.displayName)
                }
                if let depth = viewModel.parameters.seabedDepthMeters {
                    LabeledContent("Seabed Depth") {
                        Text(heightText(depth))
                            .monospacedDigit()
                    }
                }
                LabeledContent("Fetched") {
                    Text(location.fetchedAt, format: .dateTime)
                }
            } footer: {
                Text(viewModel.datum.explanation)
                    .font(.caption)
            }
        }
        .navigationTitle(location.name)
        .toolbar {
            ToolbarItem {
                NavigationLink {
                    TideCalendarView(location: location, parameters: viewModel.parameters)
                } label: {
                    Label("Calendar", systemImage: "calendar")
                }
            }
            ToolbarItem {
                Menu("Location Options", systemImage: "ellipsis.circle") {
                    Button("Edit Location", systemImage: "pencil") {
                        isEditing = true
                    }
                    Button("Delete", systemImage: "trash", role: .destructive) {
                        isConfirmingDelete = true
                    }
                    Section("Datum") {
                        DatumPicker()
                    }
                }
            }
        }
        .sheet(isPresented: $isEditing) {
            EditLocationView(location: location)
        }
        .confirmationDialog(
            "Delete Location",
            isPresented: $isConfirmingDelete,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                delete()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("\(location.name) and its offline tide data will be removed.")
        }
        .onAppear {
            viewModel.setDatum(datum)
            viewModel.reloadIfStale()
        }
        .onChange(of: datum) { _, newDatum in
            viewModel.setDatum(newDatum)
        }
        .onChange(of: location.parametersJSON) { _, _ in
            // The location was moved: recompute from the new parameters.
            if let parameters = location.parameters {
                viewModel.replace(parameters: parameters)
            }
        }
    }

    private func delete() {
        selection = nil
        modelContext.delete(location)
    }

    private var currentTideRow: some View {
        HStack(alignment: .center) {
            Image(systemName: "water.waves")
                .foregroundStyle(.tint)
            if let height = viewModel.currentHeightMeters {
                Text(heightText(height))
                    .font(.system(.largeTitle, design: .rounded, weight: .semibold))
                    .monospacedDigit()
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(Date.now, format: .dateTime.hour().minute())
                    .foregroundStyle(.secondary)
                moonSummary
            }
        }
    }

    /// The Moon today: icon plus lunar age, the other half of a tide table.
    private var moonSummary: some View {
        let moon = MoonPhase(date: .now)
        return HStack(spacing: 4) {
            Image(systemName: moon.phase.systemImageName)
            Text(
                "Moon age \(moon.ageDays, format: .number.precision(.fractionLength(1))) days"
            )
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .monospacedDigit()
    }

    private var dayNavigator: some View {
        HStack(spacing: 12) {
            Button("Previous Day", systemImage: "chevron.backward") {
                viewModel.goToPreviousDay()
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)

            DatePicker(
                "Date",
                selection: Binding(
                    get: { viewModel.dayStart },
                    set: { viewModel.setDay($0) }
                ),
                displayedComponents: .date
            )
            .labelsHidden()
            .frame(maxWidth: .infinity, alignment: .center)

            Button("Next Day", systemImage: "chevron.forward") {
                viewModel.goToNextDay()
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)

            Button("Today") {
                viewModel.goToToday()
            }
            .buttonStyle(.bordered)
            .disabled(viewModel.isShowingToday)
        }
        .lineLimit(1)
    }

    /// Sunrise and sunset of the displayed day. Hidden on polar days, where
    /// the chart shading alone tells the story.
    @ViewBuilder private var sunTimesRow: some View {
        if let sunrise = viewModel.sunrise, let sunset = viewModel.sunset {
            HStack {
                Label {
                    Text(sunrise, format: .dateTime.hour().minute())
                } icon: {
                    Image(systemName: "sunrise.fill")
                        .foregroundStyle(.orange)
                }
                .accessibilityLabel(Text("Sunrise"))
                .accessibilityValue(Text(sunrise, format: .dateTime.hour().minute()))
                Spacer()
                Label {
                    Text(sunset, format: .dateTime.hour().minute())
                } icon: {
                    Image(systemName: "sunset.fill")
                        .foregroundStyle(.indigo)
                }
                .accessibilityLabel(Text("Sunset"))
                .accessibilityValue(Text(sunset, format: .dateTime.hour().minute()))
            }
            .monospacedDigit()
            .foregroundStyle(.secondary)
        }
    }

    private var chart: some View {
        Chart {
            // Night bands go first so every other mark draws above them.
            ForEach(viewModel.nightIntervals, id: \.start) { interval in
                RectangleMark(
                    xStart: .value("Time", interval.start),
                    xEnd: .value("Time", interval.end)
                )
                .foregroundStyle(Self.nightFill)
            }

            ForEach(viewModel.levels, id: \.time) { level in
                LineMark(
                    x: .value("Time", level.time),
                    y: .value("Height", level.heightMeters)
                )
                .interpolationMethod(.catmullRom)
                AreaMark(
                    x: .value("Time", level.time),
                    y: .value("Height", level.heightMeters)
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(.linearGradient(
                    colors: [Color.accentColor.opacity(0.3), Color.accentColor.opacity(0.02)],
                    startPoint: .top,
                    endPoint: .bottom
                ))
            }

            ForEach(viewModel.extrema) { extremum in
                PointMark(
                    x: .value("Time", extremum.time),
                    y: .value("Height", extremum.heightMeters)
                )
                .foregroundStyle(extremum.kind == .high ? Color.blue : Color.orange)
                .symbolSize(40)
            }

            if isNowVisible {
                RuleMark(x: .value("Now", Date.now))
                    .foregroundStyle(.red.opacity(0.7))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .annotation(position: .top, alignment: .leading) {
                        Text("Now")
                            .font(.caption2)
                            .foregroundStyle(.red)
                    }
                if let height = viewModel.currentHeightMeters {
                    PointMark(
                        x: .value("Now", Date.now),
                        y: .value("Height", height)
                    )
                    .foregroundStyle(.red)
                    .symbolSize(60)
                }
            }
        }
        .chartXScale(domain: viewModel.windowStart...viewModel.windowEnd)
        .chartYAxisLabel(String(localized: "Tide Height (m)"))
    }

    /// Shade the night lies under: dark and bluish so daylight reads bright
    /// in both color schemes without drowning the tide curve.
    private static let nightFill = Color.indigo.opacity(0.14)

    private var isNowVisible: Bool {
        (viewModel.windowStart...viewModel.windowEnd).contains(.now)
    }

    private func extremumRow(_ extremum: LocationDetailViewModel.ExtremumItem) -> some View {
        HStack {
            Label {
                Text(extremum.kind == .high ? "High Tide" : "Low Tide")
            } icon: {
                Image(systemName: extremum.kind == .high ? "arrow.up.circle.fill" : "arrow.down.circle.fill")
                    .foregroundStyle(extremum.kind == .high ? Color.blue : Color.orange)
            }
            Spacer()
            VStack(alignment: .trailing) {
                Text(extremum.time, format: .dateTime.weekday().hour().minute())
                Text(heightText(extremum.heightMeters))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .monospacedDigit()
        }
    }

    private func heightText(_ meters: Double) -> String {
        Measurement(value: meters, unit: UnitLength.meters)
            .formatted(.measurement(width: .abbreviated, usage: .asProvided, numberFormatStyle: .number.precision(.fractionLength(2))))
    }
}
