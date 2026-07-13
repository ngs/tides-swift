import Foundation

/// A single predicted tide level.
public struct TideLevel: Equatable, Sendable {
    public var time: Date
    /// Tide height in meters relative to the datum in the parameters.
    public var heightMeters: Double

    public init(time: Date, heightMeters: Double) {
        self.time = time
        self.heightMeters = heightMeters
    }
}

/// High/low water events in a prediction window.
public struct TideExtrema: Equatable, Sendable {
    public var highs: [TideLevel]
    public var lows: [TideLevel]

    public init(highs: [TideLevel], lows: [TideLevel]) {
        self.highs = highs
        self.lows = lows
    }
}

/// Offline harmonic tide predictor.
///
/// Computes `h(t) = msl + Σ f_k(t)·A_k·cos(ω_k·Δt + V_k + u_k(t) − φ_k)`
/// where Δt is hours since `parameters.referenceTime`, V_k is the
/// server-provided equilibrium argument at the reference epoch, and the nodal
/// corrections f/u are evaluated locally at the absolute prediction time.
///
/// This is a port of the Go implementation in tides-api
/// (`internal/domain/tide.go`, `nodal.go`) and is validated against golden
/// fixtures generated from it (see Tests/TidesCoreTests/Fixtures).
public struct TidePredictor: Sendable {
    public let parameters: HarmonicParameters
    /// Datum every returned height is expressed against.
    public let datum: TideDatum

    /// Constant added to the MSL-referenced harmonic sum so the result is
    /// measured from `datum`. Chart datum sits *below* mean sea level, so a
    /// height measured from it is larger by `chartDatumOffsetMeters`.
    private let datumOffsetMeters: Double

    /// - Parameter datum: defaults to `.meanSeaLevel`, which is the datum of
    ///   the parameters as served by tides-api and the one the golden fixtures
    ///   are generated against. Callers that display heights the way Japanese
    ///   tide tables do pass `.chartDatum` explicitly.
    public init(parameters: HarmonicParameters, datum: TideDatum = .meanSeaLevel) {
        self.parameters = parameters
        self.datum = datum
        switch datum {
        case .meanSeaLevel:
            datumOffsetMeters = 0
        case .chartDatum:
            datumOffsetMeters = parameters.chartDatumOffsetMeters
        }
    }

    /// Tide height at an instant, in meters relative to the datum.
    ///
    /// Port of Go `domain.CalculateTideHeight`, plus the constant datum shift.
    public func height(at time: Date) -> Double {
        // Δt: hours since the phase reference epoch.
        let deltaHours = time.timeIntervalSince(parameters.referenceTime) / 3_600.0
        // Nodal corrections depend on the absolute time being predicted
        // (e.g. the 18.6-year lunar node cycle), not on the reference epoch.
        let absHours = time.timeIntervalSince1970 / 3_600.0

        var height = parameters.mslMeters + datumOffsetMeters
        for constituent in parameters.constituents {
            let correction = AstronomicalNodalCorrection.factors(
                constituent: constituent.name,
                hoursSinceUnixEpoch: absHours
            )

            // Greenwich phase lag convention (no longitude term):
            // h(t) = f A cos(ωΔt + V(t_ref) + u − φ)
            // V(t_ref) is precomputed by the server (equilibriumArgumentDegrees).
            let phaseAngleDeg = constituent.speedDegPerHour * deltaHours
                + constituent.equilibriumArgumentDegrees
                + correction.uDegrees
                - constituent.phaseDegrees

            height += correction.f * constituent.amplitudeMeters * cos(deg2rad(phaseAngleDeg))
        }
        return height
    }

    /// Time series between two instants at a fixed interval.
    ///
    /// Port of Go `domain.GeneratePredictions`: enumerates `start`,
    /// `start + interval`, ... while the time does not exceed `end`
    /// (inclusive of `end` when it falls on the grid).
    public func predictions(
        from start: Date,
        to end: Date,
        interval: TimeInterval
    ) -> [TideLevel] {
        var result: [TideLevel] = []
        var time = start
        while time <= end {
            result.append(TideLevel(time: time, heightMeters: height(at: time)))
            time = time.addingTimeInterval(interval)
        }
        return result
    }

    /// High/low water events between two instants, refined to sub-interval
    /// precision by parabolic interpolation.
    ///
    /// Matches the tides-api behavior (`internal/usecase/predict.go`):
    /// extrema are located on a 1-minute grid, capped at 86,400 points
    /// (coarsened to whole minutes beyond that), then refined with
    /// `RefineExtrema` (parabolic interpolation).
    public func extrema(from start: Date, to end: Date) -> TideExtrema {
        // Base grid: 1 minute. Cap the total number of grid points
        // (60 days at 1-minute resolution) and coarsen beyond that,
        // keeping the interval a whole number of minutes.
        let maxPrecisePoints = 86_400.0
        var preciseInterval: TimeInterval = 60
        let span = end.timeIntervalSince(start)
        if (span / preciseInterval).rounded(.down) > maxPrecisePoints {
            preciseInterval = span / maxPrecisePoints
            let rem = preciseInterval.truncatingRemainder(dividingBy: 60)
            if rem != 0 {
                preciseInterval += 60 - rem
            }
        }
        let grid = predictions(from: start, to: end, interval: preciseInterval)
        return Self.refineExtrema(predictions: grid, extrema: Self.findExtrema(in: grid))
    }

    // MARK: - Extrema detection (port of Go FindExtrema / RefineExtrema)

    /// Indices of local maxima and minima in a time series.
    /// Port of Go `domain.FindExtrema` (first-derivative sign change;
    /// plateaus are skipped).
    static func findExtrema(in predictions: [TideLevel]) -> (highs: [Int], lows: [Int]) {
        guard predictions.count >= 3 else {
            return ([], [])
        }

        var highs: [Int] = []
        var lows: [Int] = []
        for index in 1..<(predictions.count - 1) {
            let prev = predictions[index - 1].heightMeters
            let curr = predictions[index].heightMeters
            let next = predictions[index + 1].heightMeters

            if curr > prev, curr > next {
                highs.append(index)
            }
            if curr < prev, curr < next {
                lows.append(index)
            }
        }
        return (highs, lows)
    }

    /// Parabolic interpolation of a discrete extremum using its neighbors.
    /// Port of Go `domain.RefineExtremum`.
    static func refineExtremum(
        before: TideLevel,
        peak: TideLevel,
        after: TideLevel
    ) -> TideLevel {
        // Time spacing in hours.
        let dt1 = peak.time.timeIntervalSince(before.time) / 3_600.0
        let dt2 = after.time.timeIntervalSince(peak.time) / 3_600.0

        // Non-uniform spacing: return the discrete peak.
        if abs(dt1 - dt2) > 1e-6 {
            return peak
        }

        // Parabola y = a x² + b x + c with vertex at x = -b / (2a),
        // via finite differences.
        let h0 = before.heightMeters
        let h1 = peak.heightMeters
        let h2 = after.heightMeters

        let a = (h2 - 2 * h1 + h0) / (2 * dt1 * dt1)
        let b = (h2 - h0) / (2 * dt1)

        // Nearly linear: return the discrete peak.
        if abs(a) < 1e-10 {
            return peak
        }

        let dtVertex = -b / (2 * a)

        // Clamp to a reasonable range (within one interval).
        if abs(dtVertex) > dt1 {
            return peak
        }

        return TideLevel(
            time: peak.time.addingTimeInterval(dtVertex * 3_600.0),
            heightMeters: h1 + b * dtVertex + a * dtVertex * dtVertex
        )
    }

    /// Applies parabolic refinement to all extrema.
    /// Port of Go `domain.RefineExtrema`.
    static func refineExtrema(
        predictions: [TideLevel],
        extrema: (highs: [Int], lows: [Int])
    ) -> TideExtrema {
        guard predictions.count >= 3 else {
            return TideExtrema(
                highs: extrema.highs.map { predictions[$0] },
                lows: extrema.lows.map { predictions[$0] }
            )
        }

        func refine(_ indices: [Int]) -> [TideLevel] {
            var refined: [TideLevel] = []
            refined.reserveCapacity(indices.count)
            for idx in indices {
                guard idx >= 1, idx < predictions.count - 1 else {
                    refined.append(predictions[idx])
                    continue
                }
                refined.append(refineExtremum(
                    before: predictions[idx - 1],
                    peak: predictions[idx],
                    after: predictions[idx + 1]
                ))
            }
            return refined.sorted { $0.time < $1.time }
        }

        return TideExtrema(highs: refine(extrema.highs), lows: refine(extrema.lows))
    }
}
