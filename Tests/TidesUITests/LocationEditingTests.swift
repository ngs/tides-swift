import CoreLocation
import Foundation
import MapKit
import Testing
import TidesCore
import TidesPlatform
import TidesUI

// MARK: - Mocks

private struct StubAPIClient: TidesAPIClientProtocol {
    var result: Result<HarmonicParameters, TidesAPIError>
    func fetchParameters(latitude _: Double, longitude _: Double) async throws -> HarmonicParameters {
        try result.get()
    }
}

private struct StubGeocoder: ReverseGeocoding {
    var name: String?
    func suggestedName(latitude _: Double, longitude _: Double) async -> String? {
        name
    }
}

private struct StubPlaceSearch: PlaceSearching {
    var results: [PlaceSuggestion] = []
    var error: TidesAPIError?

    func search(query _: String, near _: MKCoordinateRegion?) async throws -> [PlaceSuggestion] {
        if let error {
            throw error
        }
        return results
    }
}

private func makeParameters(mslMeters: Double = 0) -> HarmonicParameters {
    HarmonicParameters(
        location: .init(lat: 35.0, lon: 139.75),
        stationID: nil,
        source: "fes",
        datum: "MSL",
        mslMeters: mslMeters,
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

private func makeSavedLocation() throws -> SavedLocation {
    try SavedLocation(
        name: "Old Name",
        latitude: 35.0,
        longitude: 139.75,
        parameters: makeParameters()
    )
}

// MARK: - Search and zoom

@MainActor
struct AddLocationSearchTests {
    private let suggestion = PlaceSuggestion(
        name: "Enoshima",
        subtitle: "Fujisawa, Kanagawa",
        latitude: 35.299,
        longitude: 139.48
    )

    private func makeViewModel(search: StubPlaceSearch) -> AddLocationViewModel {
        AddLocationViewModel(
            client: StubAPIClient(result: .success(makeParameters())),
            geocoder: StubGeocoder(name: nil),
            placeSearch: search
        )
    }

    @Test
    func searchPopulatesResults() async {
        let viewModel = makeViewModel(search: StubPlaceSearch(results: [suggestion]))
        viewModel.searchQuery = "Enoshima"

        await viewModel.search()

        #expect(viewModel.searchResults == [suggestion])
        #expect(viewModel.errorMessage == nil)
    }

    @Test
    func emptySearchResultsReportAMessage() async {
        let viewModel = makeViewModel(search: StubPlaceSearch(results: []))
        viewModel.searchQuery = "nowhere"

        await viewModel.search()

        #expect(viewModel.searchResults.isEmpty)
        #expect(viewModel.errorMessage != nil)
    }

    @Test
    func blankQueryDoesNotSearch() async {
        let viewModel = makeViewModel(search: StubPlaceSearch(results: [suggestion]))
        viewModel.searchQuery = "   "

        await viewModel.search()

        #expect(viewModel.searchResults.isEmpty)
        #expect(viewModel.errorMessage == nil)
    }

    @Test
    func selectingASuggestionSelectsItsCoordinateNameAndZoomsIn() async {
        let viewModel = makeViewModel(search: StubPlaceSearch(results: [suggestion]))
        viewModel.searchQuery = "Enoshima"
        await viewModel.search()

        viewModel.select(suggestion: suggestion)

        #expect(viewModel.selectedCoordinate?.latitude == suggestion.latitude)
        #expect(viewModel.selectedCoordinate?.longitude == suggestion.longitude)
        #expect(viewModel.locationName == "Enoshima")
        #expect(viewModel.searchResults.isEmpty)

        let camera = viewModel.pendingCamera
        #expect(camera?.spanDegrees == AddLocationViewModel.selectionSpanDegrees)
        #expect(camera?.latitude == suggestion.latitude)
    }

    @Test
    func zoomInAndOutScaleTheVisibleSpanWithinLimits() {
        let viewModel = makeViewModel(search: StubPlaceSearch())
        viewModel.mapCameraChanged(
            to: MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 35, longitude: 139),
                span: MKCoordinateSpan(latitudeDelta: 1.0, longitudeDelta: 1.0)
            )
        )

        viewModel.zoomIn()
        #expect(viewModel.pendingCamera?.spanDegrees == 0.5)
        viewModel.consumePendingCamera()

        viewModel.zoomOut()
        #expect(viewModel.pendingCamera?.spanDegrees == 1.0)
        viewModel.consumePendingCamera()

        // Zooming out repeatedly must stop at the maximum span.
        for _ in 0..<20 {
            viewModel.zoomOut()
            viewModel.consumePendingCamera()
        }
        #expect(viewModel.visibleRegion?.span.latitudeDelta == AddLocationViewModel.maximumSpanDegrees)
    }

    /// Without a nearby landmark the suggestion must be the coordinate itself,
    /// never a region-wide name.
    @Test
    func fallbackNameIsTheCoordinateWhenNoLandmarkIsKnown() async {
        let viewModel = makeViewModel(search: StubPlaceSearch())
        viewModel.select(coordinate: CLLocationCoordinate2D(latitude: 35.0, longitude: 139.75))

        await viewModel.fetchParameters()

        #expect(viewModel.locationName == "35.000, 139.750")
    }
}

// MARK: - Editing

@MainActor
struct EditLocationViewModelTests {
    @Test
    func renamingDoesNotRefetchParameters() async throws {
        let location = try makeSavedLocation()
        let viewModel = EditLocationViewModel(
            location: location,
            client: StubAPIClient(
                result: .failure(TidesAPIError(message: "must not be called", statusCode: 500))
            )
        )

        viewModel.name = "  Tokyo Bay  "
        #expect(!viewModel.coordinateChanged)
        let saved = await viewModel.save()

        #expect(saved)
        #expect(location.name == "Tokyo Bay")
        #expect(location.latitude == 35.0)
        #expect(viewModel.errorMessage == nil)
    }

    @Test
    func movingRefetchesParametersAndUpdatesCoordinates() async throws {
        let location = try makeSavedLocation()
        let updated = makeParameters(mslMeters: 1.25)
        let viewModel = EditLocationViewModel(
            location: location,
            client: StubAPIClient(result: .success(updated))
        )

        viewModel.latitudeText = "34.5"
        viewModel.longitudeText = "135.25"
        #expect(viewModel.coordinateChanged)

        let saved = await viewModel.save()

        #expect(saved)
        #expect(location.latitude == 34.5)
        #expect(location.longitude == 135.25)
        #expect(location.parameters == updated)
    }

    /// A failed download must leave the location untouched rather than pairing
    /// old parameters with new coordinates.
    @Test
    func failedRefetchKeepsTheOriginalLocation() async throws {
        let location = try makeSavedLocation()
        let original = location.parameters
        let viewModel = EditLocationViewModel(
            location: location,
            client: StubAPIClient(
                result: .failure(TidesAPIError(message: "no valid constituents", statusCode: 404))
            )
        )

        viewModel.name = "Somewhere Else"
        viewModel.latitudeText = "10.0"
        viewModel.longitudeText = "20.0"
        let saved = await viewModel.save()

        #expect(!saved)
        #expect(viewModel.errorMessage == "no valid constituents")
        #expect(location.latitude == 35.0)
        #expect(location.longitude == 139.75)
        #expect(location.name == "Old Name")
        #expect(location.parameters == original)
    }

    @Test
    func invalidCoordinatesCannotBeSaved() throws {
        let location = try makeSavedLocation()
        let viewModel = EditLocationViewModel(
            location: location,
            client: StubAPIClient(result: .success(makeParameters()))
        )

        viewModel.latitudeText = "91"
        #expect(viewModel.enteredCoordinate == nil)
        #expect(!viewModel.canSave)

        viewModel.latitudeText = "35"
        viewModel.longitudeText = "abc"
        #expect(viewModel.enteredCoordinate == nil)
        #expect(!viewModel.canSave)

        viewModel.longitudeText = "139.75"
        viewModel.name = "   "
        #expect(!viewModel.canSave)
    }

    @Test
    func mapTapUpdatesTheCoordinateFields() throws {
        let location = try makeSavedLocation()
        let viewModel = EditLocationViewModel(
            location: location,
            client: StubAPIClient(result: .success(makeParameters()))
        )

        viewModel.select(coordinate: CLLocationCoordinate2D(latitude: 12.5, longitude: -34.25))

        #expect(viewModel.enteredCoordinate?.latitude == 12.5)
        #expect(viewModel.enteredCoordinate?.longitude == -34.25)
        #expect(viewModel.coordinateChanged)
    }
}
