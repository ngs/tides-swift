import SwiftUI
import TidesCore

extension MoonPhase.Phase {
    /// The phase under the name an almanac gives it.
    var localizedName: LocalizedStringResource {
        switch self {
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
}

extension MoonPhase {
    /// The phase by name, with the Moon's age in days after it — "Waxing
    /// Crescent (0.6)".
    ///
    /// The name is what a reader recognizes at a glance; the age is the number
    /// a tide table is read against, and the two belong together. The
    /// parentheses are part of the localized format, because a language that
    /// sets them full-width (Japanese, Chinese) needs to say so.
    var namedAge: Text {
        Text("\(Text(phase.localizedName)) (\(ageDays, format: .number.precision(.fractionLength(1))))")
    }
}
