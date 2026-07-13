import CoreLocation
import Foundation
import Testing
import TidesCore
import TidesPlatform
import TidesUI

// MARK: - Mocks

private struct MockAPIClient: TidesAPIClientProtocol {
    var result: Result<HarmonicParameters, TidesAPIError>

    func fetchParameters(latitude _: Double, longitude _: Double) async throws -> HarmonicParameters {
        try result.get()
    }
}

private struct MockGeocoder: ReverseGeocoding {
    var name: String?

    func suggestedName(latitude _: Double, longitude _: Double) async -> String? {
        name
    }
}

private func makeParameters() -> HarmonicParameters {
    HarmonicParameters(
        location: .init(lat: 35.0, lon: 139.75),
        stationID: nil,
        source: "fes",
        datum: "MSL",
        mslMeters: 0.0,
        seabedDepthMeters: 12.5,
        referenceTime: Date(timeIntervalSince1970: 1_325_376_000),  // 2012-01-01T00:00:00Z
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

// MARK: - Tests

@MainActor
struct AddLocationViewModelTests {
    @Test
    func fetchSucceedsAndSuggestsName() async {
        let viewModel = AddLocationViewModel(
            client: MockAPIClient(result: .success(makeParameters())),
            geocoder: MockGeocoder(name: "Tokyo Bay")
        )
        viewModel.select(coordinate: CLLocationCoordinate2D(latitude: 35.0, longitude: 139.75))

        await viewModel.fetchParameters()

        #expect(viewModel.phase == .naming)
        #expect(viewModel.fetchedParameters == makeParameters())
        #expect(viewModel.locationName == "Tokyo Bay")
        #expect(viewModel.errorMessage == nil)
        #expect(viewModel.canSave)
    }

    @Test
    func fetchSucceedsWithoutGeocoderResultUsesFallbackName() async {
        let viewModel = AddLocationViewModel(
            client: MockAPIClient(result: .success(makeParameters())),
            geocoder: MockGeocoder(name: nil)
        )
        viewModel.select(coordinate: CLLocationCoordinate2D(latitude: 35.0, longitude: 139.75))

        await viewModel.fetchParameters()

        #expect(viewModel.phase == .naming)
        #expect(!viewModel.locationName.isEmpty)
    }

    @Test
    func fetchFailureShowsServerErrorMessage() async {
        let viewModel = AddLocationViewModel(
            client: MockAPIClient(
                result: .failure(TidesAPIError(message: "no valid constituents", statusCode: 404))
            ),
            geocoder: MockGeocoder(name: nil)
        )
        viewModel.select(coordinate: CLLocationCoordinate2D(latitude: 35.68, longitude: 139.76))

        await viewModel.fetchParameters()

        #expect(viewModel.phase == .selecting)
        #expect(viewModel.errorMessage == "no valid constituents")
        #expect(viewModel.fetchedParameters == nil)
        #expect(!viewModel.canSave)
    }

    @Test
    func fetchWithoutCoordinateDoesNothing() async {
        let viewModel = AddLocationViewModel(
            client: MockAPIClient(result: .success(makeParameters())),
            geocoder: MockGeocoder(name: nil)
        )

        await viewModel.fetchParameters()

        #expect(viewModel.phase == .selecting)
        #expect(viewModel.fetchedParameters == nil)
    }

    @Test
    func selectingNewCoordinateResetsFetchedParameters() async {
        let viewModel = AddLocationViewModel(
            client: MockAPIClient(result: .success(makeParameters())),
            geocoder: MockGeocoder(name: "Tokyo Bay")
        )
        viewModel.select(coordinate: CLLocationCoordinate2D(latitude: 35.0, longitude: 139.75))
        await viewModel.fetchParameters()
        #expect(viewModel.phase == .naming)

        viewModel.select(coordinate: CLLocationCoordinate2D(latitude: 34.0, longitude: 135.0))

        #expect(viewModel.phase == .selecting)
        #expect(viewModel.fetchedParameters == nil)
        #expect(!viewModel.canSave)
    }

    @Test
    func cannotSaveWithBlankName() async {
        let viewModel = AddLocationViewModel(
            client: MockAPIClient(result: .success(makeParameters())),
            geocoder: MockGeocoder(name: nil)
        )
        viewModel.select(coordinate: CLLocationCoordinate2D(latitude: 35.0, longitude: 139.75))
        await viewModel.fetchParameters()

        viewModel.locationName = "   "

        #expect(!viewModel.canSave)
        #expect(viewModel.makeSavedLocation() == nil)
    }

    @Test
    func makeSavedLocationRoundTripsParameters() async throws {
        let viewModel = AddLocationViewModel(
            client: MockAPIClient(result: .success(makeParameters())),
            geocoder: MockGeocoder(name: "Tokyo Bay")
        )
        viewModel.select(coordinate: CLLocationCoordinate2D(latitude: 35.0, longitude: 139.75))
        await viewModel.fetchParameters()

        let saved = try #require(viewModel.makeSavedLocation())

        #expect(saved.name == "Tokyo Bay")
        #expect(saved.latitude == 35.0)
        #expect(saved.longitude == 139.75)
        #expect(saved.parameters == makeParameters())
    }
}
