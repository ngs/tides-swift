import SwiftUI
import TidesCore
import TidesPlatform

/// Month calendar for a saved location: each day shows the Moon's phase and
/// that day's high and low waters. Selecting a day lists all of its tides.
struct TideCalendarView: View {
    let location: SavedLocation
    @AppStorage(TideDatumSettings.storageKey, store: TideDatumSettings.defaults)
    private var datum: TideDatum = TideDatumSettings.defaultDatum
    @State private var viewModel: TideCalendarViewModel

    init(location: SavedLocation, parameters: HarmonicParameters) {
        self.location = location
        _viewModel = State(initialValue: TideCalendarViewModel(parameters: parameters))
    }

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 7)

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                monthHeader
                weekdayHeader
                grid
                if let day = viewModel.selectedDay {
                    selectedDayDetail(day)
                }
            }
            .padding()
        }
        .navigationTitle(location.name)
        #if os(iOS) || os(visionOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
            .onChange(of: datum) { _, newDatum in
                viewModel.setDatum(newDatum)
            }
    }

    // MARK: - Header

    private var monthHeader: some View {
        HStack(spacing: 12) {
            Button("Previous Month", systemImage: "chevron.backward") {
                viewModel.goToPreviousMonth()
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)

            Text(viewModel.monthTitle, format: .dateTime.year().month(.wide))
                .font(.headline)
                .frame(maxWidth: .infinity)

            Button("Next Month", systemImage: "chevron.forward") {
                viewModel.goToNextMonth()
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)

            Button("Today") {
                viewModel.goToToday()
            }
            .buttonStyle(.bordered)
            .disabled(viewModel.isShowingCurrentMonth)
        }
        .lineLimit(1)
    }

    private var weekdayHeader: some View {
        HStack(spacing: 2) {
            ForEach(viewModel.weekdaySymbols, id: \.self) { symbol in
                Text(symbol)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: - Grid

    private var grid: some View {
        LazyVGrid(columns: columns, spacing: 2) {
            ForEach(viewModel.days) { day in
                Button {
                    viewModel.selectedDay = day
                } label: {
                    dayCell(day)
                }
                .buttonStyle(.plain)
                .disabled(!day.isInDisplayedMonth)
            }
        }
    }

    private func dayCell(_ day: TideCalendarViewModel.Day) -> some View {
        VStack(spacing: 2) {
            HStack(spacing: 3) {
                Text("\(day.dayOfMonth)")
                    .font(.caption.weight(day.isToday ? .bold : .regular))
                    .monospacedDigit()
                Image(systemName: day.moon.phase.systemImageName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(moonAccessibilityLabel(day.moon))
            }

            if let high = day.highs.first {
                tideTime(high.time, systemImage: "arrow.up", color: .blue)
            }
            if let low = day.lows.first {
                tideTime(low.time, systemImage: "arrow.down", color: .orange)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 58)
        .padding(.vertical, 4)
        .background(cellBackground(day))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay {
            if day.isToday {
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(Color.accentColor, lineWidth: 1)
            }
        }
        .opacity(day.isInDisplayedMonth ? 1 : 0.3)
    }

    private func tideTime(_ date: Date, systemImage: String, color: Color) -> some View {
        HStack(spacing: 1) {
            Image(systemName: systemImage)
                .foregroundStyle(color)
            Text(date, format: .dateTime.hour().minute())
                .monospacedDigit()
        }
        .font(.system(size: 9))
        .lineLimit(1)
        .minimumScaleFactor(0.7)
    }

    @ViewBuilder
    private func cellBackground(_ day: TideCalendarViewModel.Day) -> some View {
        if day == viewModel.selectedDay {
            Color.accentColor.opacity(0.18)
        } else {
            Color.secondary.opacity(0.08)
        }
    }

    // MARK: - Selected day

    private func selectedDayDetail(_ day: TideCalendarViewModel.Day) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider()

            Text(day.date, format: .dateTime.weekday(.wide).month().day())
                .font(.headline)

            HStack(spacing: 8) {
                Image(systemName: day.moon.phase.systemImageName)
                    .font(.title3)
                VStack(alignment: .leading, spacing: 1) {
                    Text(moonPhaseName(day.moon.phase))
                        .font(.subheadline)
                    Text(
                        "Moon age \(day.moon.ageDays, format: .number.precision(.fractionLength(1))) days · \(day.moon.illuminatedFraction, format: .percent.precision(.fractionLength(0))) lit"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                }
            }

            if day.highs.isEmpty && day.lows.isEmpty {
                Text("No high or low tides in this period.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(tideEvents(for: day), id: \.time) { event in
                    HStack {
                        Label {
                            Text(event.isHigh ? "High Tide" : "Low Tide")
                        } icon: {
                            Image(
                                systemName: event.isHigh
                                    ? "arrow.up.circle.fill"
                                    : "arrow.down.circle.fill"
                            )
                            .foregroundStyle(event.isHigh ? Color.blue : Color.orange)
                        }
                        Spacer()
                        Text(event.time, format: .dateTime.hour().minute())
                        Text(heightText(event.heightMeters))
                            .foregroundStyle(.secondary)
                    }
                    .font(.subheadline)
                    .monospacedDigit()
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private struct TideEvent {
        var time: Date
        var heightMeters: Double
        var isHigh: Bool
    }

    private func tideEvents(for day: TideCalendarViewModel.Day) -> [TideEvent] {
        let highs = day.highs.map {
            TideEvent(time: $0.time, heightMeters: $0.heightMeters, isHigh: true)
        }
        let lows = day.lows.map {
            TideEvent(time: $0.time, heightMeters: $0.heightMeters, isHigh: false)
        }
        return (highs + lows).sorted { $0.time < $1.time }
    }

    private func moonPhaseName(_ phase: MoonPhase.Phase) -> LocalizedStringKey {
        switch phase {
        case .newMoon: "New Moon"
        case .waxingCrescent: "Waxing Crescent"
        case .firstQuarter: "First Quarter"
        case .waxingGibbous: "Waxing Gibbous"
        case .fullMoon: "Full Moon"
        case .waningGibbous: "Waning Gibbous"
        case .lastQuarter: "Last Quarter"
        case .waningCrescent: "Waning Crescent"
        }
    }

    private func moonAccessibilityLabel(_ moon: MoonPhase) -> Text {
        Text(moonPhaseName(moon.phase))
    }

    private func heightText(_ meters: Double) -> String {
        Measurement(value: meters, unit: UnitLength.meters)
            .formatted(
                .measurement(
                    width: .abbreviated,
                    usage: .asProvided,
                    numberFormatStyle: .number.precision(.fractionLength(2))
                )
            )
    }
}
