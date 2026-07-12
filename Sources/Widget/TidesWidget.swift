import SwiftUI
import TidesCore
import WidgetKit

/// Home screen / lock screen widget showing the current tide and the next high
/// and low water for a saved location. Everything is computed offline.
struct TidesWidget: Widget {
    static let kind = "TidesWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: Self.kind,
            intent: SelectLocationIntent.self,
            provider: TideTimelineProvider()
        ) { entry in
            TidesWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Tides")
        .description("Current tide and next high and low water for a saved location.")
        .supportedFamilies(Self.supportedFamilies)
    }

    /// Accessory families exist on the iOS lock screen only; macOS supports
    /// the system families in Notification Center.
    private static var supportedFamilies: [WidgetFamily] {
        #if os(iOS)
        [.systemSmall, .systemMedium, .accessoryRectangular, .accessoryInline]
        #else
        [.systemSmall, .systemMedium]
        #endif
    }
}

struct TidesWidgetView: View {
    @Environment(\.widgetFamily)
    private var family
    let entry: TideEntry

    var body: some View {
        if entry.locationName == nil {
            emptyView
        } else {
            #if os(iOS)
            switch family {
            case .accessoryInline:
                inlineView
            case .accessoryRectangular:
                rectangularView
            default:
                standardView
            }
            #else
            standardView
            #endif
        }
    }

    private var emptyView: some View {
        VStack(spacing: 4) {
            Image(systemName: "mappin.slash")
            Text("No Saved Locations")
                .font(.caption)
                .multilineTextAlignment(.center)
        }
        .foregroundStyle(.secondary)
    }

    private var inlineView: some View {
        Text("\(heightText(entry.currentHeightMeters)) · \(nextEventShortText)")
    }

    private var rectangularView: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(entry.locationName ?? "")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text(heightText(entry.currentHeightMeters))
                .font(.headline)
                .monospacedDigit()
            Text(nextEventShortText)
                .font(.caption2)
                .monospacedDigit()
        }
    }

    private var standardView: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(entry.locationName ?? "", systemImage: "water.waves")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Text(heightText(entry.currentHeightMeters))
                .font(.system(.title, design: .rounded, weight: .semibold))
                .monospacedDigit()

            Spacer(minLength: 0)

            if let high = entry.nextHigh {
                eventRow(
                    title: "High",
                    level: high,
                    systemImage: "arrow.up.circle.fill",
                    color: .blue
                )
            }
            if let low = entry.nextLow {
                eventRow(
                    title: "Low",
                    level: low,
                    systemImage: "arrow.down.circle.fill",
                    color: .orange
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func eventRow(
        title: LocalizedStringKey,
        level: TideLevel,
        systemImage: String,
        color: Color
    ) -> some View {
        HStack(spacing: 4) {
            Image(systemName: systemImage)
                .foregroundStyle(color)
            Text(title)
            Spacer()
            Text(level.time, format: .dateTime.hour().minute())
            Text(heightText(level.heightMeters))
                .foregroundStyle(.secondary)
        }
        .font(.caption2)
        .monospacedDigit()
        .lineLimit(1)
    }

    /// Time and height of whichever event comes first.
    private var nextEventShortText: String {
        let next: (level: TideLevel, isHigh: Bool)?
        switch (entry.nextHigh, entry.nextLow) {
        case let (high?, low?):
            next = high.time <= low.time ? (high, true) : (low, false)
        case let (high?, nil):
            next = (high, true)
        case let (nil, low?):
            next = (low, false)
        case (nil, nil):
            next = nil
        }
        guard let next else {
            return heightText(nil)
        }
        let label = next.isHigh
            ? String(localized: "High")
            : String(localized: "Low")
        let time = next.level.time.formatted(.dateTime.hour().minute())
        return "\(label) \(time) \(heightText(next.level.heightMeters))"
    }

    private func heightText(_ meters: Double?) -> String {
        guard let meters else { return "--" }
        return Measurement(value: meters, unit: UnitLength.meters)
            .formatted(
                .measurement(
                    width: .abbreviated,
                    usage: .asProvided,
                    numberFormatStyle: .number.precision(.fractionLength(2))
                )
            )
    }
}

@main
struct TidesWidgetBundle: WidgetBundle {
    var body: some Widget {
        TidesWidget()
    }
}
