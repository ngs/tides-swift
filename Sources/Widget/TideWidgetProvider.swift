import AppIntents
import Foundation
import SwiftData
import TidesCore
import TidesPlatform
import WidgetKit

/// One rendered state of the tide widget.
struct TideEntry: TimelineEntry {
    var date: Date
    /// Name of the location shown, or `nil` when no location is available.
    var locationName: String?
    var currentHeightMeters: Double?
    var nextHigh: TideLevel?
    var nextLow: TideLevel?

    /// The Moon at the entry's date; tides and the Moon are read together.
    var moon: MoonPhase {
        MoonPhase(date: date)
    }

    /// Placeholder shown while the widget loads or in the gallery.
    static func placeholder(date: Date = .now) -> TideEntry {
        TideEntry(
            date: date,
            locationName: String(localized: "Tokyo Bay"),
            currentHeightMeters: 0.82,
            nextHigh: TideLevel(time: date.addingTimeInterval(3 * 3_600), heightMeters: 1.42),
            nextLow: TideLevel(time: date.addingTimeInterval(9 * 3_600), heightMeters: 0.11)
        )
    }

    /// Entry shown when the user has not saved any location yet.
    static func empty(date: Date = .now) -> TideEntry {
        TideEntry(date: date)
    }
}

/// Timeline provider: reads the saved locations from the App Group SwiftData
/// store and computes the tide entirely offline with `TidePredictor`.
struct TideTimelineProvider: AppIntentTimelineProvider {
    /// How many entries the timeline holds, one per `entryInterval`.
    private static let entryCount = 12
    /// Spacing between entries (the widget refreshes at least this often).
    private static let entryInterval: TimeInterval = 30 * 60

    func placeholder(in _: Context) -> TideEntry {
        .placeholder()
    }

    func snapshot(for configuration: SelectLocationIntent, in _: Context) async -> TideEntry {
        entries(for: configuration, from: .now).first ?? .empty()
    }

    func timeline(
        for configuration: SelectLocationIntent,
        in _: Context
    ) async -> Timeline<TideEntry> {
        let now = Date.now
        let entries = entries(for: configuration, from: now)
        guard let last = entries.last else {
            return Timeline(entries: [.empty(date: now)], policy: .after(now.addingTimeInterval(3_600)))
        }
        return Timeline(entries: entries, policy: .after(last.date))
    }

    /// Builds one entry per refresh point for the configured location.
    private func entries(for configuration: SelectLocationIntent, from start: Date) -> [TideEntry] {
        guard
            let location = resolveLocation(id: configuration.location?.id),
            let parameters = location.parameters
        else {
            return [.empty(date: start)]
        }

        let predictor = TidePredictor(parameters: parameters)
        return (0..<Self.entryCount).map { index in
            let date = start.addingTimeInterval(Double(index) * Self.entryInterval)
            let extrema = predictor.extrema(from: date, to: date.addingTimeInterval(24 * 3_600))
            return TideEntry(
                date: date,
                locationName: location.name,
                currentHeightMeters: predictor.height(at: date),
                nextHigh: extrema.highs.first,
                nextLow: extrema.lows.first
            )
        }
    }

    /// Configured location, falling back to the first saved one so a freshly
    /// added widget shows data without being configured first.
    private func resolveLocation(id: String?) -> SavedLocation? {
        let context = ModelContext(TidesModelContainer.shared)
        let descriptor = FetchDescriptor<SavedLocation>(
            sortBy: [SortDescriptor(\.createdAt)]
        )
        guard let locations = try? context.fetch(descriptor), !locations.isEmpty else {
            return nil
        }
        guard let id else { return locations.first }
        return locations.first { SavedLocationEntity.id(for: $0) == id } ?? locations.first
    }
}
