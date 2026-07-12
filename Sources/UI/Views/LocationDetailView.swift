import Charts
import SwiftUI
import TidesCore
import TidesPlatform

/// Tide detail screen: two-day tide curve, current level, high/low water list
/// and day navigation. Works fully offline from the saved parameters.
struct LocationDetailView: View {
    let location: SavedLocation

    var body: some View {
        if let parameters = location.parameters {
            LocationDetailContentView(location: location, parameters: parameters)
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
    @State private var viewModel: LocationDetailViewModel

    init(location: SavedLocation, parameters: HarmonicParameters) {
        self.location = location
        _viewModel = State(initialValue: LocationDetailViewModel(parameters: parameters))
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
                LabeledContent("Fetched") {
                    Text(location.fetchedAt, format: .dateTime)
                }
            }
        }
        .navigationTitle(location.name)
        .onAppear {
            viewModel.reload()
        }
    }

    private var currentTideRow: some View {
        HStack(alignment: .firstTextBaseline) {
            Image(systemName: "water.waves")
                .foregroundStyle(.tint)
            if let height = viewModel.currentHeightMeters {
                Text(heightText(height))
                    .font(.system(.largeTitle, design: .rounded, weight: .semibold))
                    .monospacedDigit()
            }
            Spacer()
            Text(Date.now, format: .dateTime.hour().minute())
                .foregroundStyle(.secondary)
        }
    }

    private var dayNavigator: some View {
        HStack {
            Button("Previous Day", systemImage: "chevron.backward") {
                viewModel.goToPreviousDay()
            }
            .labelStyle(.iconOnly)
            Spacer()
            DatePicker(
                "Date",
                selection: Binding(
                    get: { viewModel.dayStart },
                    set: { viewModel.setDay($0) }
                ),
                displayedComponents: .date
            )
            .labelsHidden()
            Button("Today") {
                viewModel.goToToday()
            }
            .buttonStyle(.bordered)
            Spacer()
            Button("Next Day", systemImage: "chevron.forward") {
                viewModel.goToNextDay()
            }
            .labelStyle(.iconOnly)
        }
        .buttonStyle(.borderless)
    }

    private var chart: some View {
        Chart {
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
