import Foundation

/// Vertical reference surface tide heights are expressed against.
public enum TideDatum: String, CaseIterable, Codable, Sendable {
    /// Mean sea level: the datum the harmonic parameters themselves use
    /// (`msl_m` plus the harmonic sum). Heights go negative around low water.
    case meanSeaLevel = "msl"
    /// Chart datum (Z0, approximate lowest low water). It lies
    /// `HarmonicParameters.chartDatumOffsetMeters` *below* mean sea level, so
    /// heights measured from it are almost always positive. This is the datum
    /// used by the Japanese tide tables (JMA / Japan Coast Guard).
    case chartDatum = "z0"
}

/// The App Group shared by the app, the widget extension and the watch app.
///
/// macOS requires the identifier to carry the Team ID prefix, while iOS,
/// visionOS and watchOS use the bare identifier. Both forms refer to the same
/// App Group registered in the developer portal.
public enum TidesAppGroup {
    public static let identifier: String = {
        #if os(macOS)
        return "3Y8APYUG2G.group.io.ngs.Tides"
        #else
        return "group.io.ngs.Tides"
        #endif
    }()

    /// Defaults suite backed by the App Group container, falling back to the
    /// standard defaults where the entitlement is unavailable (previews, tests,
    /// unsigned builds). The app still works; the widget just cannot see the
    /// value.
    ///
    /// One shared instance: `@AppStorage` observes the store object it is given,
    /// so every target must bind to the same one. `UserDefaults` is thread-safe,
    /// hence `nonisolated(unsafe)`.
    // The SwiftLint build CI runs cannot parse `nonisolated(unsafe)` and
    // misreports the modifier order.
    // swiftlint:disable:next modifier_order
    nonisolated(unsafe) public static let defaults = UserDefaults(suiteName: identifier) ?? .standard
}

/// User preference for the datum tide heights are displayed against.
///
/// Lives in `TidesCore` (Foundation only) so the engine, the widget and the
/// watch app can read it without SwiftUI. SwiftUI callers bind to the same
/// suite and key with `@AppStorage`.
public enum TideDatumSettings {
    /// Defaults key shared with the `@AppStorage` bindings.
    public static let storageKey = "displayDatum"

    /// Japanese tide tables are the reference for this app, so chart datum wins.
    public static let defaultDatum = TideDatum.chartDatum

    /// Defaults suite holding the preference.
    public static var defaults: UserDefaults { TidesAppGroup.defaults }

    /// The datum currently selected by the user.
    public static var current: TideDatum {
        guard
            let raw = defaults.string(forKey: storageKey),
            let datum = TideDatum(rawValue: raw)
        else {
            return defaultDatum
        }
        return datum
    }
}
