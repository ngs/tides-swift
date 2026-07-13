import Foundation

/// The Moon's phase at an instant.
///
/// Computed from the Moon–Sun elongation using the leading periodic terms of
/// Meeus, *Astronomical Algorithms* (ch. 25 and 47). Accuracy is well within a
/// degree of elongation, which is far more than a calendar icon or a lunar age
/// in days requires. Depends on Foundation only, like the rest of TidesCore.
public struct MoonPhase: Equatable, Sendable {
    /// The eight phases conventionally shown on a calendar.
    public enum Phase: String, CaseIterable, Sendable {
        case newMoon
        case waxingCrescent
        case firstQuarter
        case waxingGibbous
        case fullMoon
        case waningGibbous
        case lastQuarter
        case waningCrescent

        /// SF Symbol drawing the illuminated part of the disc.
        public var systemImageName: String {
            switch self {
            case .newMoon: "moonphase.new.moon"
            case .waxingCrescent: "moonphase.waxing.crescent"
            case .firstQuarter: "moonphase.first.quarter"
            case .waxingGibbous: "moonphase.waxing.gibbous"
            case .fullMoon: "moonphase.full.moon"
            case .waningGibbous: "moonphase.waning.gibbous"
            case .lastQuarter: "moonphase.last.quarter"
            case .waningCrescent: "moonphase.waning.crescent"
            }
        }
    }

    /// Mean length of a lunation, in days.
    public static let synodicMonthDays = 29.530588853

    /// Elongation of the Moon from the Sun, in degrees [0, 360).
    /// 0° is new moon, 180° is full moon.
    public let elongationDegrees: Double
    /// Lunar age in days since the last new moon, in [0, `synodicMonthDays`).
    public let ageDays: Double
    /// Fraction of the disc that is lit, 0 (new) to 1 (full).
    public let illuminatedFraction: Double
    /// The named phase, for icons and labels.
    public let phase: Phase

    /// True while the Moon is growing towards full.
    public var isWaxing: Bool {
        elongationDegrees < 180
    }

    public init(date: Date) {
        let centuries = Self.julianCenturies(from: date)
        let elongation = Self.normalizeDegrees(
            Self.moonLongitude(centuries: centuries) - Self.sunLongitude(centuries: centuries)
        )

        self.elongationDegrees = elongation
        self.ageDays = Self.synodicMonthDays * elongation / 360.0
        // Ignoring the Moon's ecliptic latitude (always < 6°) changes the lit
        // fraction by less than 0.5%.
        self.illuminatedFraction = (1 - cos(Self.radians(elongation))) / 2
        self.phase = Self.phase(elongationDegrees: elongation)
    }

    /// Buckets the elongation into the eight calendar phases. The four exact
    /// phases (new, quarters, full) get a narrow window of ±1 day-equivalent so
    /// a day is only labelled "full moon" when it really is one.
    static func phase(elongationDegrees elongation: Double) -> Phase {
        // One day of a lunation, in degrees of elongation.
        let dayDegrees = 360.0 / synodicMonthDays
        let half = dayDegrees / 2

        switch elongation {
        case ..<half:
            return .newMoon
        case ..<(90 - half):
            return .waxingCrescent
        case ..<(90 + half):
            return .firstQuarter
        case ..<(180 - half):
            return .waxingGibbous
        case ..<(180 + half):
            return .fullMoon
        case ..<(270 - half):
            return .waningGibbous
        case ..<(270 + half):
            return .lastQuarter
        case ..<(360 - half):
            return .waningCrescent
        default:
            return .newMoon
        }
    }

    // MARK: - Astronomy

    /// Julian centuries since J2000.0 (2000-01-01 12:00 TT).
    private static func julianCenturies(from date: Date) -> Double {
        let julianDay = date.timeIntervalSince1970 / 86_400.0 + 2_440_587.5
        return (julianDay - 2_451_545.0) / 36_525.0
    }

    /// Apparent ecliptic longitude of the Sun, in degrees.
    private static func sunLongitude(centuries: Double) -> Double {
        // Mean longitude and mean anomaly.
        let meanLongitude = 280.46646 + 36_000.76983 * centuries
        let meanAnomaly = radians(357.52911 + 35_999.05029 * centuries)

        // Equation of the center.
        let center = 1.914602 * sin(meanAnomaly)
            + 0.019993 * sin(2 * meanAnomaly)
            + 0.000289 * sin(3 * meanAnomaly)

        return normalizeDegrees(meanLongitude + center)
    }

    /// Apparent ecliptic longitude of the Moon, in degrees.
    private static func moonLongitude(centuries: Double) -> Double {
        // Meeus ch. 47: mean longitude, elongation, anomalies, argument of
        // latitude.
        let meanLongitude = 218.3164477 + 481_267.88123421 * centuries
        let elongation = radians(297.8501921 + 445_267.1114034 * centuries)
        let sunAnomaly = radians(357.5291092 + 35_999.0502909 * centuries)
        let moonAnomaly = radians(134.9633964 + 477_198.8675055 * centuries)
        let latitudeArgument = radians(93.2720950 + 483_202.0175233 * centuries)

        // Leading periodic terms of the longitude series.
        let periodic = 6.289 * sin(moonAnomaly)
            + 1.274 * sin(2 * elongation - moonAnomaly)
            + 0.658 * sin(2 * elongation)
            + 0.214 * sin(2 * moonAnomaly)
            - 0.186 * sin(sunAnomaly)
            - 0.114 * sin(2 * latitudeArgument)

        return normalizeDegrees(meanLongitude + periodic)
    }

    private static func radians(_ degrees: Double) -> Double {
        degrees * .pi / 180
    }

    private static func normalizeDegrees(_ degrees: Double) -> Double {
        var normalized = degrees.truncatingRemainder(dividingBy: 360)
        if normalized < 0 {
            normalized += 360
        }
        return normalized
    }
}
