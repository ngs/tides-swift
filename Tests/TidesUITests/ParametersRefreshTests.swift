import Foundation
import Testing
import TidesCore
import TidesPlatform
import TidesUI

// MARK: - Mocks

/// Returns parameters carrying the requested coordinate, and fails for the
/// coordinates listed in `failingLatitudes` — enough to pin what a partly
/// failing refresh does.
private struct RecordingAPIClient: TidesAPIClientProtocol {
    var failingLatitudes: Set<Double> = []

    func fetchParameters(latitude: Double, longitude: Double) async throws -> HarmonicParameters {
        if failingLatitudes.contains(latitude) {
            throw TidesAPIError(message: "offline", statusCode: 503)
        }
        return makeParameters(latitude: latitude, longitude: longitude, offset: 1.25)
    }
}

private func makeParameters(
    latitude: Double,
    longitude: Double,
    offset: Double? = nil
) -> HarmonicParameters {
    HarmonicParameters(
        location: .init(lat: latitude, lon: longitude),
        stationID: nil,
        source: "fes",
        datum: "MSL",
        mslMeters: 0,
        serverChartDatumOffsetMeters: offset,
        seabedDepthMeters: nil,
        referenceTime: Date(timeIntervalSince1970: 1_325_376_000),
        constituents: [
            .init(
                name: "M2",
                speedDegPerHour: 28.9841042,
                amplitudeMeters: 0.5,
                phaseDegrees: 120.0,
                equilibriumArgumentDegrees: 30.0
            )
        ]
    )
}

private func makeSavedLocation(name: String, latitude: Double, longitude: Double) throws -> SavedLocation {
    try SavedLocation(
        name: name,
        latitude: latitude,
        longitude: longitude,
        parameters: makeParameters(latitude: latitude, longitude: longitude),
        fetchedAt: Date(timeIntervalSince1970: 1_700_000_000)
    )
}

// MARK: - Tests

@MainActor
struct ParametersRefreshViewModelTests {
    /// Every location is refetched at its own coordinate and left where it is.
    @Test
    func refreshUpdatesEveryLocationInPlace() async throws {
        let locations = [
            try makeSavedLocation(name: "Tokyo", latitude: 35.0, longitude: 139.75),
            try makeSavedLocation(name: "Osaka", latitude: 34.6, longitude: 135.4)
        ]
        let viewModel = ParametersRefreshViewModel(client: RecordingAPIClient())

        let updated = await viewModel.refresh(locations)

        #expect(updated == 2)
        #expect(viewModel.failedNames.isEmpty)
        #expect(viewModel.errorMessage == nil)
        // Idle again, so the button comes back.
        #expect(!viewModel.isRefreshing)
        #expect(viewModel.progress == nil)

        for location in locations {
            #expect(location.parameters?.serverChartDatumOffsetMeters == 1.25)
            #expect(location.parameters?.location?.lat == location.latitude)
            #expect(location.fetchedAt > Date(timeIntervalSince1970: 1_700_000_000))
        }
    }

    /// One unreachable point cannot deny the others their refresh, and the ones
    /// that failed keep the parameters they already had.
    @Test
    func oneFailureLeavesItsParametersAndDoesNotStopTheWalk() async throws {
        let failing = try makeSavedLocation(name: "Osaka", latitude: 34.6, longitude: 135.4)
        let original = failing.parameters
        let locations = [
            try makeSavedLocation(name: "Tokyo", latitude: 35.0, longitude: 139.75),
            failing,
            try makeSavedLocation(name: "Naha", latitude: 26.2, longitude: 127.7)
        ]
        let viewModel = ParametersRefreshViewModel(
            client: RecordingAPIClient(failingLatitudes: [34.6])
        )

        let updated = await viewModel.refresh(locations)

        #expect(updated == 2)
        #expect(viewModel.failedNames == ["Osaka"])
        #expect(viewModel.errorMessage != nil)
        #expect(failing.parameters == original)
        #expect(locations[0].parameters?.serverChartDatumOffsetMeters == 1.25)
        #expect(locations[2].parameters?.serverChartDatumOffsetMeters == 1.25)
    }

    /// Nothing saved, nothing to refresh — and no error to report for it.
    @Test
    func refreshingAnEmptyListDoesNothing() async {
        let viewModel = ParametersRefreshViewModel(client: RecordingAPIClient())

        let updated = await viewModel.refresh([])

        #expect(updated == 0)
        #expect(viewModel.errorMessage == nil)
        #expect(!viewModel.isRefreshing)
    }
}
