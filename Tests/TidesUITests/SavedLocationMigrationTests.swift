import Foundation
import Testing
import TidesCore
import TidesPlatform

/// `SavedLocation.parameters` is the single point every consumer (detail
/// screen, widget, watch app) decodes through, so the pre-redesign datum
/// migration is applied there. These tests pin that behavior without touching
/// the persisted JSON or the CloudKit schema.
struct SavedLocationMigrationTests {
    private static let referenceTime = Date(timeIntervalSince1970: 1_325_376_000)

    private func makeParameters(
        mslMeters: Double,
        serverChartDatumOffsetMeters: Double? = nil
    ) -> HarmonicParameters {
        HarmonicParameters(
            location: .init(lat: 35.0, lon: 139.75),
            stationID: nil,
            source: "fes",
            datum: "MSL",
            mslMeters: mslMeters,
            serverChartDatumOffsetMeters: serverChartDatumOffsetMeters,
            seabedDepthMeters: nil,
            referenceTime: Self.referenceTime,
            constituents: [
                .init(name: "M2", speedDegPerHour: 28.9841042, amplitudeMeters: 0.55,
                      phaseDegrees: 120, equilibriumArgumentDegrees: 30),
                .init(name: "S2", speedDegPerHour: 30.0, amplitudeMeters: 0.24,
                      phaseDegrees: 150, equilibriumArgumentDegrees: 10),
                .init(name: "K1", speedDegPerHour: 15.0410686, amplitudeMeters: 0.21,
                      phaseDegrees: 200, equilibriumArgumentDegrees: 80),
                .init(name: "O1", speedDegPerHour: 13.9430356, amplitudeMeters: 0.17,
                      phaseDegrees: 180, equilibriumArgumentDegrees: 200)
            ]
        )
    }

    private func makeSavedLocation(from parameters: HarmonicParameters) throws -> SavedLocation {
        try SavedLocation(
            name: "Cached",
            latitude: 35.0,
            longitude: 139.75,
            parameters: parameters
        )
    }

    /// A location cached before the redesign (non-zero `msl_m`, no server
    /// offset) reads back normalized: `msl_m` is 0 and the old intercept is now
    /// the chart datum offset, so the double-counting is gone.
    @Test
    func legacyCacheIsMigratedOnRead() throws {
        let location = try makeSavedLocation(from: makeParameters(mslMeters: 0.83))
        let params = try #require(location.parameters)

        #expect(params.mslMeters == 0)
        #expect(params.serverChartDatumOffsetMeters == 0.83)
        #expect(params.chartDatumOffsetMeters == 0.83)
        #expect(params.isLegacyDatumFormat == false)
    }

    /// Current-contract cache passes through untouched — no accidental
    /// re-migration on every read.
    @Test
    func currentContractCacheIsUnchanged() throws {
        let stored = makeParameters(mslMeters: 0, serverChartDatumOffsetMeters: 0.9)
        let location = try makeSavedLocation(from: stored)
        let params = try #require(location.parameters)

        #expect(params.mslMeters == 0)
        #expect(params.serverChartDatumOffsetMeters == 0.9)
        #expect(params.chartDatumOffsetMeters == 0.9)
    }
}
