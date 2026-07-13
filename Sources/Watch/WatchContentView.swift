import SwiftUI
import TidesCore

/// Watch root view: guidance when no location is set, otherwise the current
/// tide and next high/low water.
struct WatchContentView: View {
    @Environment(WatchTideStore.self)
    private var store
    /// Datum chosen in the iPhone app, shared through the App Group defaults.
    @AppStorage(TideDatumSettings.storageKey, store: TideDatumSettings.defaults)
    private var datum: TideDatum = TideDatumSettings.defaultDatum

    var body: some View {
        NavigationStack {
            if let location = store.location {
                WatchTideView(location: location, datum: datum)
            } else {
                ContentUnavailableView(
                    "No Location Set",
                    systemImage: "mappin.slash",
                    description: Text("Add a location from the iPhone app.")
                )
                .navigationTitle("Tides")
            }
        }
    }
}

/// Current tide height and the next high/low water for the stored location.
struct WatchTideView: View {
    let location: WatchTideStore.StoredLocation
    let datum: TideDatum

    private var predictor: TidePredictor {
        TidePredictor(parameters: location.parameters, datum: datum)
    }

    var body: some View {
        let now = Date.now
        let extrema = predictor.extrema(from: now, to: now.addingTimeInterval(24 * 60 * 60))
        let nextHigh = extrema.highs.first
        let nextLow = extrema.lows.first

        List {
            Section("Current Tide") {
                HStack(alignment: .firstTextBaseline) {
                    Image(systemName: "water.waves")
                        .foregroundStyle(.tint)
                    Text(heightText(predictor.height(at: now)))
                        .font(.system(.title2, design: .rounded, weight: .semibold))
                        .monospacedDigit()
                    Spacer()
                    Image(systemName: MoonPhase(date: now).phase.systemImageName)
                        .foregroundStyle(.secondary)
                }
            }
            Section {
                if let nextHigh {
                    row(title: "Next High Tide", level: nextHigh, systemImage: "arrow.up.circle.fill", color: .blue)
                }
                if let nextLow {
                    row(title: "Next Low Tide", level: nextLow, systemImage: "arrow.down.circle.fill", color: .orange)
                }
            }
        }
        .navigationTitle(location.name)
    }

    private func row(
        title: LocalizedStringKey,
        level: TideLevel,
        systemImage: String,
        color: Color
    ) -> some View {
        VStack(alignment: .leading) {
            Label {
                Text(title)
            } icon: {
                Image(systemName: systemImage)
                    .foregroundStyle(color)
            }
            .font(.caption)
            HStack {
                Text(level.time, format: .dateTime.hour().minute())
                Spacer()
                Text(heightText(level.heightMeters))
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
