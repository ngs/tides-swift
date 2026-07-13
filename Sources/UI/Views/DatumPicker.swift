import SwiftUI
import TidesCore
// The widget extension is embedded in the iOS and macOS builds only, and
// `WidgetCenter` needs visionOS 26, so the reload is limited to those two.
#if os(iOS) || os(macOS)
import WidgetKit
#endif

extension TideDatum {
    /// Menu / picker label.
    var displayName: LocalizedStringKey {
        switch self {
        case .chartDatum:
            "Chart Datum (Z0)"
        case .meanSeaLevel:
            "Mean Sea Level (MSL)"
        }
    }

    /// Explanation shown under the tide details.
    var explanation: LocalizedStringKey {
        switch self {
        case .chartDatum:
            "Heights are measured from chart datum (Z0), the level used by Japanese tide tables. It lies below mean sea level by the combined amplitude of the four principal constituents, so heights are almost always positive."
        case .meanSeaLevel:
            "Heights are measured from mean sea level (MSL). A negative height simply means the water is below the local average — normal around low water."
        }
    }
}

/// Picker for the datum every screen (and the widget and the watch app) shows
/// heights against. The selection is stored in the App Group defaults, so all
/// targets pick it up.
struct DatumPicker: View {
    @AppStorage(TideDatumSettings.storageKey, store: TideDatumSettings.defaults)
    private var datum: TideDatum = TideDatumSettings.defaultDatum

    var body: some View {
        Picker("Datum", selection: $datum) {
            ForEach(TideDatum.allCases, id: \.self) { value in
                Text(value.displayName).tag(value)
            }
        }
        // Inline inside a menu: both options are listed with a checkmark on the
        // selected one, on iOS and macOS alike.
        .pickerStyle(.inline)
        .onChange(of: datum) { _, _ in
            // The widget renders from the same preference; drop its timeline.
            #if os(iOS) || os(macOS)
            WidgetCenter.shared.reloadAllTimelines()
            #endif
        }
    }
}
