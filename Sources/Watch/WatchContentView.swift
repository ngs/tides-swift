import SwiftData
import SwiftUI
import TidesCore
import TidesPlatform

/// Watch root view: guidance when no location has been saved, the tide itself
/// when a single location is saved, and a picker when there are several.
///
/// The locations come from the SwiftData store shared with the phone through
/// CloudKit; nothing is entered on the watch.
struct WatchContentView: View {
    @Query(sort: [SortDescriptor(\SavedLocation.sortOrder), SortDescriptor(\SavedLocation.createdAt)])
    private var locations: [SavedLocation]
    /// Displayed datum. The preference is per device — App Groups do not span
    /// devices, so the phone's selection is not visible here and the watch
    /// stays on the default (chart datum) until it gets its own setting or a
    /// WatchConnectivity sync.
    @AppStorage(TideDatumSettings.storageKey, store: TideDatumSettings.defaults)
    private var datum: TideDatum = TideDatumSettings.defaultDatum

    var body: some View {
        NavigationStack {
            switch locations.count {
            case 0:
                ContentUnavailableView(
                    "No Location Set",
                    systemImage: "mappin.slash",
                    description: Text("Add a location from the iPhone app.")
                )
                .navigationTitle("Tides")
            case 1:
                // Keep the familiar single-location layout: no list to tap
                // through when there is nothing to choose from.
                WatchTideView(location: locations[0], datum: datum)
            default:
                List(locations) { location in
                    NavigationLink(location.name) {
                        WatchTideView(location: location, datum: datum)
                    }
                }
                .navigationTitle("Locations")
            }
        }
    }
}

/// Current tide height and the next high/low water for a saved location.
struct WatchTideView: View {
    let location: SavedLocation
    let datum: TideDatum

    var body: some View {
        Group {
            if let parameters = location.parameters {
                tideList(predictor: TidePredictor(parameters: parameters, datum: datum))
            } else {
                ContentUnavailableView(
                    "Tide Data Unavailable",
                    systemImage: "exclamationmark.triangle",
                    description: Text("The saved parameters for this location could not be read.")
                )
            }
        }
        .navigationTitle(location.name)
    }

    private func tideList(predictor: TidePredictor) -> some View {
        let now = Date.now
        let extrema = predictor.extrema(from: now, to: now.addingTimeInterval(24 * 60 * 60))
        // Parabolic refinement can nudge the first extremum slightly before
        // `now`; only events still ahead count as "next".
        let nextHigh = extrema.highs.first { $0.time >= now }
        let nextLow = extrema.lows.first { $0.time >= now }

        return List {
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
