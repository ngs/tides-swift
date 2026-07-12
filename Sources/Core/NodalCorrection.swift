import Foundation

/// Degrees to radians.
@inlinable
func deg2rad(_ deg: Double) -> Double {
    deg * .pi / 180.0
}

/// Radians to degrees.
@inlinable
func rad2deg(_ rad: Double) -> Double {
    rad * 180.0 / .pi
}

/// Normalizes an angle in degrees to [0, 360).
func normalizeDegrees(_ deg: Double) -> Double {
    var normalized = deg.truncatingRemainder(dividingBy: 360.0)
    if normalized < 0 {
        normalized += 360.0
    }
    return normalized
}

/// Astronomical nodal corrections based on Schureman (1958) and Foreman (1977).
///
/// Port of tides-api `internal/domain/nodal.go`
/// (`AstronomicalNodalCorrection` with the built-in pyTMD-derived
/// coefficients; no external coefficient file support).
enum AstronomicalNodalCorrection {
    /// Fundamental astronomical arguments (degrees), Schureman (1958).
    struct Arguments: Sendable {
        /// Mean longitude of lunar ascending node (N).
        var lunarNode: Double
        /// Mean longitude of the Moon (s).
        var s: Double
        /// Mean longitude of the Sun (h).
        var h: Double
        /// Mean longitude of lunar perigee (p).
        var perigee: Double
        /// Mean longitude of solar perigee (p_s).
        var solarPerigee: Double
        /// Inclination of lunar orbit (I).
        var inclination: Double
        /// Nutation in longitude (ν).
        var nu: Double
        /// Nutation factor (ξ).
        var xi: Double
    }

    /// Computes astronomical arguments at absolute time `hours`
    /// (hours since Unix epoch). Based on Schureman (1958) formulas.
    static func arguments(hoursSinceUnixEpoch hours: Double) -> Arguments {
        // Convert hours to days since epoch (J2000.0 = 2000-01-01 12:00:00 UTC).
        // Unix epoch (1970-01-01 00:00:00) is 10957.5 days before J2000.0.
        let daysFromUnix = hours / 24.0
        let daysFromJ2000 = daysFromUnix - 10_957.5

        // Julian centuries from J2000.0.
        let centuries = daysFromJ2000 / 36_525.0

        // N: Mean longitude of lunar ascending node.
        var lunarNode = 125.04452 - 1_934.136261 * centuries
            + 0.0020708 * centuries * centuries
            + centuries * centuries * centuries / 450_000.0

        // s: Mean longitude of the Moon (Meeus/IERS; linear rate 0.5490165 deg/hr).
        var s = 218.3164477 + 481_267.88123421 * centuries
            - 0.0015786 * centuries * centuries
            + centuries * centuries * centuries / 538_841.0

        // h: Mean longitude of the Sun (linear rate 0.0410686 deg/hr).
        var h = 280.46646 + 36_000.76983 * centuries + 0.0003032 * centuries * centuries

        // p: Mean longitude of lunar perigee.
        var perigee = 83.35324 + 4_069.01363 * centuries
            - 0.0103238 * centuries * centuries
            - centuries * centuries * centuries / 80_053.0

        // ps: Mean longitude of solar perigee (perihelion).
        var solarPerigee = 282.94 + 1.7192 * centuries

        lunarNode = normalizeDegrees(lunarNode)
        s = normalizeDegrees(s)
        h = normalizeDegrees(h)
        perigee = normalizeDegrees(perigee)
        solarPerigee = normalizeDegrees(solarPerigee)

        // Inclination of lunar orbit.
        let inclinationRad = acos(0.91370 - 0.03569 * cos(deg2rad(lunarNode)))
        let inclination = rad2deg(inclinationRad)

        // Nutation factor (nu) and xi.
        let nuRad = asin(0.08978 * sin(deg2rad(lunarNode)) / sin(inclinationRad))
        let nu = rad2deg(nuRad)

        let xi = lunarNode - 2.0 * nu

        return Arguments(
            lunarNode: lunarNode,
            s: s,
            h: h,
            perigee: perigee,
            solarPerigee: solarPerigee,
            inclination: inclination,
            nu: nu,
            xi: xi
        )
    }

    /// Returns the nodal correction amplitude factor `f` and phase correction
    /// `u` (degrees) at absolute time `hours` (hours since Unix epoch).
    static func factors(
        constituent: String,
        hoursSinceUnixEpoch hours: Double
    ) -> (f: Double, uDegrees: Double) {
        let args = arguments(hoursSinceUnixEpoch: hours)

        // Built-in nonlinear coefficients (pyTMD-derived), if available.
        guard let coeff = builtInNonlinearCoeffs[constituent] else {
            // Constituents without coefficients: identity (no correction).
            return (1.0, 0.0)
        }

        let nodeRad = deg2rad(args.lunarNode)
        // term1 = sum a_k sin(kN), term2 = b0 + sum b_k cos(kN)
        var term1 = 0.0
        for (harmonic, coefficient) in coeff.term1Sin {
            term1 += coefficient * sin(Double(harmonic) * nodeRad)
        }
        var term2 = coeff.term2Const
        for (harmonic, coefficient) in coeff.term2Cos {
            term2 += coefficient * cos(Double(harmonic) * nodeRad)
        }
        let factor = (term1 * term1 + term2 * term2).squareRoot()
        let phaseDeg = rad2deg(atan2(term1, term2))
        return (factor, phaseDeg)
    }

    /// Nonlinear nodal coefficients: f, u computed via sqrt/atan2 of
    /// sin/cos series in N (radians). Terms are (harmonic k, coefficient).
    private struct NonlinearCoeff: Sendable {
        /// a_k for sin(kN).
        var term1Sin: [(Int, Double)]
        /// b0.
        var term2Const: Double
        /// b_k for cos(kN).
        var term2Cos: [(Int, Double)]
    }

    // Shared coefficients for constituents with identical sin/cos terms.
    private static let m2SinCosCoeffs: [(Int, Double)] = [(1, -0.03731), (2, 0.00052)]
    private static let s2SinCosCoeffs: [(Int, Double)] = [(1, 0.00225)]
    private static let n2SinCosCoeffs: [(Int, Double)] = [(1, -0.03731), (2, 0.00052)]
    private static let o1SinCosCoeffs: [(Int, Double)] = [(1, 0.189), (2, -0.0058)]
    private static let p1SinCosCoeffs: [(Int, Double)] = [(1, -0.0112)]
    private static let q1SinCosCoeffs: [(Int, Double)] = [(1, 0.1886)]

    /// Built-in coefficients for major constituents (pyTMD-derived; N in radians).
    private static let builtInNonlinearCoeffs: [String: NonlinearCoeff] = [
        // M2: Principal lunar semidiurnal.
        "M2": NonlinearCoeff(term1Sin: m2SinCosCoeffs, term2Const: 1.0, term2Cos: m2SinCosCoeffs),
        // S2: Principal solar semidiurnal (very small nodal effect).
        "S2": NonlinearCoeff(term1Sin: s2SinCosCoeffs, term2Const: 1.0, term2Cos: s2SinCosCoeffs),
        // N2: Lunar elliptical semidiurnal (same pattern as M2).
        "N2": NonlinearCoeff(term1Sin: n2SinCosCoeffs, term2Const: 1.0, term2Cos: n2SinCosCoeffs),
        // K2: Lunisolar semidiurnal.
        "K2": NonlinearCoeff(
            term1Sin: [(1, -0.3108), (2, -0.0324)],
            term2Const: 1.0,
            term2Cos: [(1, 0.2852), (2, 0.0324)]
        ),
        // K1: Lunisolar diurnal.
        "K1": NonlinearCoeff(
            term1Sin: [(1, -0.1554), (2, 0.0029)],
            term2Const: 1.0,
            term2Cos: [(1, 0.1158), (2, -0.0029)]
        ),
        // O1: Principal lunar diurnal.
        "O1": NonlinearCoeff(term1Sin: o1SinCosCoeffs, term2Const: 1.0, term2Cos: o1SinCosCoeffs),
        // P1: Principal solar diurnal.
        "P1": NonlinearCoeff(term1Sin: p1SinCosCoeffs, term2Const: 1.0, term2Cos: p1SinCosCoeffs),
        // Q1: Lunar elliptical diurnal.
        "Q1": NonlinearCoeff(term1Sin: q1SinCosCoeffs, term2Const: 1.0, term2Cos: q1SinCosCoeffs)
    ]
}
