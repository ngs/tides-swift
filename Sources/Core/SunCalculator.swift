import Foundation

/// Sunrise and sunset for one civil day at a coordinate.
public enum SolarDay: Equatable, Sendable {
    /// The Sun rises and sets on this day.
    case risesAndSets(sunrise: Date, sunset: Date)
    /// Midnight sun: the Sun stays above the horizon all day.
    case alwaysUp
    /// Polar night: the Sun stays below the horizon all day.
    case alwaysDown

    /// The sunrise time, or `nil` on polar days.
    public var sunrise: Date? {
        if case let .risesAndSets(sunrise, _) = self { return sunrise }
        return nil
    }

    /// The sunset time, or `nil` on polar days.
    public var sunset: Date? {
        if case let .risesAndSets(_, sunset) = self { return sunset }
        return nil
    }
}

/// Sunrise/sunset times from the solar position algorithm published by NOAA
/// (based on Meeus, *Astronomical Algorithms*, ch. 25). Accuracy is well
/// within a minute for the years around the present, which is more than
/// enough to shade a tide chart. Foundation only.
public enum SunCalculator {
    /// Zenith angle of the Sun's upper limb at rise/set: 90° plus standard
    /// atmospheric refraction (34′) and the solar semidiameter (16′).
    private static let zenithDegrees = 90.833

    /// Sunrise and sunset for the civil day containing `date`.
    ///
    /// - Parameter calendar: Defines the civil day (via its time zone).
    public static func day(
        containing date: Date,
        latitude: Double,
        longitude: Double,
        calendar: Calendar = .current
    ) -> SolarDay {
        let localNoon = calendar.startOfDay(for: date).addingTimeInterval(12 * 3_600)
        let noon = transit(near: localNoon, longitude: longitude)

        func halfDaySeconds(at estimate: Date) -> Double? {
            let position = position(at: estimate)
            let cosine = hourAngleCosine(
                declinationDegrees: position.declinationDegrees,
                latitude: latitude
            )
            guard abs(cosine) <= 1 else { return nil }
            // Hour angle in degrees; the Sun moves 1° in 4 minutes.
            return rad2deg(acos(cosine)) * 4 * 60
        }

        guard let noonHalfDay = halfDaySeconds(at: noon) else {
            let position = position(at: noon)
            let cosine = hourAngleCosine(
                declinationDegrees: position.declinationDegrees,
                latitude: latitude
            )
            return cosine > 1 ? .alwaysDown : .alwaysUp
        }

        // One refinement pass: recompute the hour angle with the declination
        // at the event estimate instead of at noon.
        var sunrise = noon.addingTimeInterval(-noonHalfDay)
        if let refined = halfDaySeconds(at: sunrise) {
            sunrise = noon.addingTimeInterval(-refined)
        }
        var sunset = noon.addingTimeInterval(noonHalfDay)
        if let refined = halfDaySeconds(at: sunset) {
            sunset = noon.addingTimeInterval(refined)
        }
        return .risesAndSets(sunrise: sunrise, sunset: sunset)
    }

    // MARK: - Solar position (NOAA)

    private struct SolarPosition {
        var declinationDegrees: Double
        var equationOfTimeMinutes: Double
    }

    private static func position(at date: Date) -> SolarPosition {
        let julianDay = date.timeIntervalSince1970 / 86_400.0 + 2_440_587.5
        let centuries = (julianDay - 2_451_545.0) / 36_525.0

        // Geometric mean longitude (L0) and anomaly (M) of the Sun, and the
        // eccentricity (e) of Earth's orbit.
        let meanLongitude = normalizeDegrees(280.46646 + centuries * (36_000.76983 + centuries * 0.0003032))
        let meanAnomaly = 357.52911 + centuries * (35_999.05029 - 0.0001537 * centuries)
        let eccentricity = 0.016708634 - centuries * (0.000042037 + 0.0000001267 * centuries)

        let anomalyRad = deg2rad(meanAnomaly)
        let center = sin(anomalyRad) * (1.914602 - centuries * (0.004817 + 0.000014 * centuries))
            + sin(2 * anomalyRad) * (0.019993 - 0.000101 * centuries)
            + sin(3 * anomalyRad) * 0.000289

        // Apparent longitude: true longitude corrected for nutation and
        // aberration (Ω is the longitude of the ascending lunar node).
        let omega = deg2rad(125.04 - 1_934.136 * centuries)
        let apparentLongitude = meanLongitude + center - 0.00569 - 0.00478 * sin(omega)

        // Obliquity of the ecliptic, corrected for nutation.
        let meanObliquity = 23.0
            + (26.0 + (21.448 - centuries * (46.815 + centuries * (0.00059 - centuries * 0.001813))) / 60.0) / 60.0
        let obliquity = deg2rad(meanObliquity + 0.00256 * cos(omega))

        let declination = asin(sin(obliquity) * sin(deg2rad(apparentLongitude)))

        let halfObliquityTangent = tan(obliquity / 2)
        let y = halfObliquityTangent * halfObliquityTangent
        let longitudeRad = deg2rad(meanLongitude)
        let equationOfTime = 4 * rad2deg(
            y * sin(2 * longitudeRad)
                - 2 * eccentricity * sin(anomalyRad)
                + 4 * eccentricity * y * sin(anomalyRad) * cos(2 * longitudeRad)
                - 0.5 * y * y * sin(4 * longitudeRad)
                - 1.25 * eccentricity * eccentricity * sin(2 * anomalyRad)
        )
        return SolarPosition(
            declinationDegrees: rad2deg(declination),
            equationOfTimeMinutes: equationOfTime
        )
    }

    /// The instant of solar noon nearest `estimate`.
    private static func transit(near estimate: Date, longitude: Double) -> Date {
        var transit = estimate
        for _ in 0..<2 {
            let position = position(at: transit)
            let targetUTCMinutes = 720.0 - 4.0 * longitude - position.equationOfTimeMinutes
            var deltaMinutes = targetUTCMinutes - utcMinutesOfDay(transit)
            // Wrap to the nearest transit, so the civil day's time zone offset
            // never pushes the estimate to the neighboring day.
            deltaMinutes -= 1_440 * (deltaMinutes / 1_440).rounded()
            transit = transit.addingTimeInterval(deltaMinutes * 60)
        }
        return transit
    }

    private static func utcMinutesOfDay(_ date: Date) -> Double {
        let seconds = date.timeIntervalSince1970.truncatingRemainder(dividingBy: 86_400)
        return (seconds < 0 ? seconds + 86_400 : seconds) / 60
    }

    /// Cosine of the sunrise/sunset hour angle. Values outside [-1, 1] mean
    /// the Sun never crosses the rise/set zenith that day (polar day/night).
    private static func hourAngleCosine(declinationDegrees: Double, latitude: Double) -> Double {
        let phi = deg2rad(latitude)
        let delta = deg2rad(declinationDegrees)
        return cos(deg2rad(zenithDegrees)) / (cos(phi) * cos(delta)) - tan(phi) * tan(delta)
    }
}
