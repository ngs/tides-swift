import Foundation
import Testing
import TidesCore

/// Chart datum (Z0) is defined by the Japanese tide tables as
/// `Z0 = MSL − (H_M2 + H_S2 + H_K1 + H_O1)`, so a Z0-referenced height is the
/// MSL-referenced height plus that amplitude sum.
struct TideDatumTests {
    private static let referenceTime = Date(timeIntervalSince1970: 1_325_376_000) // 2012-01-01Z

    /// Speed (deg/hr), phase lag and equilibrium argument per constituent, so a
    /// test only has to name a constituent and its amplitude.
    private struct Astronomy {
        var speed: Double
        var phase: Double
        var equilibrium: Double
    }

    private static let astronomy: [String: Astronomy] = [
        "M2": Astronomy(speed: 28.9841042, phase: 120, equilibrium: 30),
        "S2": Astronomy(speed: 30.0, phase: 150, equilibrium: 10),
        "K1": Astronomy(speed: 15.0410686, phase: 200, equilibrium: 80),
        "O1": Astronomy(speed: 13.9430356, phase: 180, equilibrium: 200),
        "N2": Astronomy(speed: 28.4397295, phase: 100, equilibrium: 50)
    ]

    private func makeParameters(
        mslMeters: Double = 0.3,
        amplitudes: KeyValuePairs<String, Double>
    ) -> HarmonicParameters {
        HarmonicParameters(
            location: nil,
            stationID: nil,
            source: "fes",
            datum: "MSL",
            mslMeters: mslMeters,
            seabedDepthMeters: nil,
            referenceTime: Self.referenceTime,
            constituents: amplitudes.map { name, amplitude in
                let astronomy = Self.astronomy[name.uppercased()] ?? Astronomy(speed: 30, phase: 0, equilibrium: 0)
                return HarmonicParameters.Constituent(
                    name: name,
                    speedDegPerHour: astronomy.speed,
                    amplitudeMeters: amplitude,
                    phaseDegrees: astronomy.phase,
                    equilibriumArgumentDegrees: astronomy.equilibrium
                )
            }
        )
    }

    /// A realistic station: the four principal constituents plus N2, which must
    /// not count towards Z0.
    private func makeTypicalParameters() -> HarmonicParameters {
        makeParameters(amplitudes: ["M2": 0.55, "S2": 0.24, "K1": 0.21, "O1": 0.17, "N2": 0.11])
    }

    @Test
    func chartDatumOffsetIsSumOfPrincipalAmplitudes() {
        let parameters = makeTypicalParameters()
        // N2 (0.11 m) is deliberately excluded.
        #expect(abs(parameters.chartDatumOffsetMeters - (0.55 + 0.24 + 0.21 + 0.17)) < 1e-12)
    }

    @Test
    func chartDatumOffsetSumsOnlyThePresentConstituents() {
        let parameters = makeParameters(amplitudes: ["M2": 0.55, "K1": 0.21])
        #expect(abs(parameters.chartDatumOffsetMeters - (0.55 + 0.21)) < 1e-12)
    }

    @Test
    func chartDatumOffsetIsZeroWithoutPrincipalConstituents() {
        let none = makeParameters(amplitudes: [:])
        #expect(none.chartDatumOffsetMeters == 0)

        let onlyMinor = makeParameters(amplitudes: ["N2": 0.11])
        #expect(onlyMinor.chartDatumOffsetMeters == 0)
    }

    @Test
    func chartDatumOffsetIgnoresConstituentNameCase() {
        let parameters = makeParameters(amplitudes: ["m2": 0.55, "o1": 0.17])
        #expect(abs(parameters.chartDatumOffsetMeters - (0.55 + 0.17)) < 1e-12)
    }

    /// Z0 lies below MSL, so switching to it raises every height by exactly the
    /// offset — the shape of the curve is untouched.
    @Test
    func chartDatumHeightsAreMSLHeightsPlusTheOffset() {
        let parameters = makeTypicalParameters()
        let msl = TidePredictor(parameters: parameters, datum: .meanSeaLevel)
        let chart = TidePredictor(parameters: parameters, datum: .chartDatum)
        let offset = parameters.chartDatumOffsetMeters
        #expect(offset > 0)

        for hour in 0..<48 {
            let time = Date(timeIntervalSince1970: 1_752_000_000 + Double(hour) * 3_600)
            let difference = chart.height(at: time) - msl.height(at: time)
            #expect(abs(difference - offset) < 1e-9, "hour \(hour): shift \(difference) != \(offset)")
        }
    }

    @Test
    func predictionsAndExtremaFollowTheDatum() {
        let parameters = makeTypicalParameters()
        let offset = parameters.chartDatumOffsetMeters
        let start = Date(timeIntervalSince1970: 1_752_000_000)
        let end = start.addingTimeInterval(24 * 3_600)
        let msl = TidePredictor(parameters: parameters, datum: .meanSeaLevel)
        let chart = TidePredictor(parameters: parameters, datum: .chartDatum)

        let mslLevels = msl.predictions(from: start, to: end, interval: 30 * 60)
        let chartLevels = chart.predictions(from: start, to: end, interval: 30 * 60)
        #expect(mslLevels.count == chartLevels.count)
        for (mslLevel, chartLevel) in zip(mslLevels, chartLevels) {
            #expect(mslLevel.time == chartLevel.time)
            #expect(abs(chartLevel.heightMeters - mslLevel.heightMeters - offset) < 1e-9)
        }

        let mslExtrema = msl.extrema(from: start, to: end)
        let chartExtrema = chart.extrema(from: start, to: end)
        #expect(!mslExtrema.highs.isEmpty)
        #expect(mslExtrema.highs.count == chartExtrema.highs.count)
        #expect(mslExtrema.lows.count == chartExtrema.lows.count)

        // Extrema keep their times; only the heights shift.
        for (mslHigh, chartHigh) in zip(mslExtrema.highs, chartExtrema.highs) {
            #expect(abs(mslHigh.time.timeIntervalSince(chartHigh.time)) < 1e-6)
            #expect(abs(chartHigh.heightMeters - mslHigh.heightMeters - offset) < 1e-9)
        }
        for (mslLow, chartLow) in zip(mslExtrema.lows, chartExtrema.lows) {
            #expect(abs(mslLow.time.timeIntervalSince(chartLow.time)) < 1e-6)
            #expect(abs(chartLow.heightMeters - mslLow.heightMeters - offset) < 1e-9)
        }
    }

    /// Low waters go negative against MSL but stay positive against Z0 — the
    /// whole point of matching the Japanese tide tables.
    @Test
    func chartDatumKeepsLowWatersPositive() {
        let parameters = makeParameters(
            mslMeters: 0,
            amplitudes: ["M2": 0.55, "S2": 0.24, "K1": 0.21, "O1": 0.17]
        )
        let start = Date(timeIntervalSince1970: 1_752_000_000)
        let end = start.addingTimeInterval(7 * 24 * 3_600)
        let msl = TidePredictor(parameters: parameters, datum: .meanSeaLevel)
        let chart = TidePredictor(parameters: parameters, datum: .chartDatum)

        let lows = msl.extrema(from: start, to: end).lows
        #expect(lows.contains { $0.heightMeters < 0 })
        for low in chart.extrema(from: start, to: end).lows {
            #expect(low.heightMeters >= 0)
        }
    }

    /// The default keeps the engine on the datum of the parameters (and of the
    /// Go golden fixtures).
    @Test
    func defaultPredictorDatumIsMeanSeaLevel() {
        let parameters = makeTypicalParameters()
        let predictor = TidePredictor(parameters: parameters)
        #expect(predictor.datum == .meanSeaLevel)
        let time = Date(timeIntervalSince1970: 1_752_000_000)
        let explicit = TidePredictor(parameters: parameters, datum: .meanSeaLevel)
        #expect(predictor.height(at: time) == explicit.height(at: time))
    }

    /// The user-facing default is Z0, and the preference round-trips through the
    /// raw values persisted in the shared defaults (the same key `@AppStorage`
    /// binds to in the app, the widget and the watch app).
    @Test
    func datumSettingsDefaultToChartDatum() {
        #expect(TideDatumSettings.defaultDatum == .chartDatum)
        #expect(TideDatum.allCases.count == 2)
        #expect(TideDatum(rawValue: "z0") == .chartDatum)
        #expect(TideDatum(rawValue: "msl") == .meanSeaLevel)

        let defaults = TideDatumSettings.defaults
        let key = TideDatumSettings.storageKey
        let saved = defaults.string(forKey: key)
        defer {
            if let saved {
                defaults.set(saved, forKey: key)
            } else {
                defaults.removeObject(forKey: key)
            }
        }

        defaults.removeObject(forKey: key)
        #expect(TideDatumSettings.current == .chartDatum)

        defaults.set(TideDatum.meanSeaLevel.rawValue, forKey: key)
        #expect(TideDatumSettings.current == .meanSeaLevel)

        defaults.set(TideDatum.chartDatum.rawValue, forKey: key)
        #expect(TideDatumSettings.current == .chartDatum)

        // An unreadable value falls back to the default rather than crashing.
        defaults.set("nonsense", forKey: key)
        #expect(TideDatumSettings.current == .chartDatum)
    }
}
