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
        .configurationDisplayName("Shiomi")
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
            HStack(spacing: 3) {
                Text(entry.locationName ?? "")
                    .lineLimit(1)
                Image(systemName: entry.moon.phase.systemImageName)
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
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
            HStack(spacing: 4) {
                Label(entry.locationName ?? "", systemImage: "water.waves")
                    .lineLimit(1)
                Spacer(minLength: 2)
                Image(systemName: entry.moon.phase.systemImageName)
            }
            .font(.caption)
            .foregroundStyle(.secondary)

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
            // The medium family has room for a third row; the small one is
            // full with the two tide events.
            if family == .systemMedium, let sunrise = entry.sunrise, let sunset = entry.sunset {
                sunTimesRow(sunrise: sunrise, sunset: sunset)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func sunTimesRow(sunrise: Date, sunset: Date) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "sunrise.fill")
                .foregroundStyle(.orange)
                .accessibilityLabel(Text("Sunrise"))
            Text(sunrise, format: .dateTime.hour().minute())
            Spacer()
            Image(systemName: "sunset.fill")
                .foregroundStyle(.indigo)
                .accessibilityLabel(Text("Sunset"))
            Text(sunset, format: .dateTime.hour().minute())
        }
        .font(.caption2)
        .monospacedDigit()
        .lineLimit(1)
        .accessibilityElement(children: .combine)
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
        let time = next.level.time.formatted(.dateTime.hour().minute())
        let height = heightText(next.level.heightMeters)
        // One phrase per event, so translators can reorder the placeholders.
        return next.isHigh
            ? String(localized: "High \(time) \(height)")
            : String(localized: "Low \(time) \(height)")
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
