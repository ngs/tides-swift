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

private func makeParameters(
    mslMeters: Double = 0,
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
    /// Decimal-pad keyboards insert "," in many locales; both separators parse.
    @Test
    func coordinateFieldsAcceptCommaDecimals() throws {
        let viewModel = EditLocationViewModel(
            location: try makeSavedLocation(),
            client: StubAPIClient(result: .success(makeParameters()))
        )

        viewModel.latitudeText = "12,5"
        viewModel.longitudeText = "-34,25"

        #expect(viewModel.enteredCoordinate?.latitude == 12.5)
        #expect(viewModel.enteredCoordinate?.longitude == -34.25)
    }

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
        // Current-contract parameters keep msl_m at 0; the refetched set is
        // distinguished by its server-supplied chart datum offset.
        let updated = makeParameters(serverChartDatumOffsetMeters: 1.25)
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

    /// Opening the sheet must not look like an edit: the fields are formatted
    /// to five decimals, and re-parsing them must not read as a coordinate
    /// change (which would re-download parameters on every save).
    @Test
    func openingTheSheetDoesNotCountAsACoordinateChange() throws {
        let location = try SavedLocation(
            name: "Nojimazaki",
            latitude: 34.8993402,
            longitude: 139.8657579,
            parameters: makeParameters()
        )
        let viewModel = EditLocationViewModel(
            location: location,
            client: StubAPIClient(
                result: .failure(TidesAPIError(message: "must not be called", statusCode: 500))
            )
        )

        #expect(!viewModel.coordinateChanged)

        // Renaming alone must therefore save without touching the network.
        viewModel.name = "Nojima"
        #expect(viewModel.canSave)
    }

    /// The edit map has the same zoom controls as the picker, clamped to the
    /// same range.
    @Test
    func zoomControlsScaleTheEditMapWithinLimits() throws {
        let location = try makeSavedLocation()
        let viewModel = EditLocationViewModel(
            location: location,
            client: StubAPIClient(result: .success(makeParameters()))
        )

        // Without any camera change yet, zooming starts from the default span.
        viewModel.zoomIn()
        #expect(viewModel.pendingCamera?.spanDegrees == EditLocationViewModel.defaultSpanDegrees / 2)
        viewModel.consumePendingCamera()

        viewModel.mapCameraChanged(
            to: MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 35, longitude: 139),
                span: MKCoordinateSpan(latitudeDelta: 1.0, longitudeDelta: 1.0)
            )
        )
        viewModel.zoomOut()
        #expect(viewModel.pendingCamera?.spanDegrees == 2.0)
        viewModel.consumePendingCamera()

        for _ in 0..<20 {
            viewModel.zoomIn()
            viewModel.consumePendingCamera()
        }
        #expect(viewModel.visibleRegion?.span.latitudeDelta == EditLocationViewModel.minimumSpanDegrees)
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

// MARK: - Calendar

@MainActor
struct TideCalendarViewModelTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo") ?? .gmt
        return calendar
    }

    private func makeViewModel(now: Date) -> TideCalendarViewModel {
        TideCalendarViewModel(
            parameters: makeParameters(),
            latitude: 35.6762,
            longitude: 139.6503,
            calendar: calendar,
            now: now
        )
    }

    /// The grid covers whole weeks and marks which days belong to the month.
    @Test
    func gridCoversWholeWeeksOfTheMonth() {
        let now = Date(timeIntervalSince1970: 1_767_225_600)  // 2026-01-01
        let viewModel = makeViewModel(now: now)

        #expect(viewModel.days.count.isMultiple(of: 7))
        #expect(viewModel.weekdaySymbols.count == 7)

        let inMonth = viewModel.days.filter(\.isInDisplayedMonth)
        #expect(inMonth.count == 31)
        #expect(inMonth.first?.dayOfMonth == 1)
        #expect(inMonth.last?.dayOfMonth == 31)
    }

    /// Every day carries its Moon phase and that day's tides.
    @Test
    func daysCarryMoonPhaseAndTides() throws {
        let now = Date(timeIntervalSince1970: 1_767_225_600)
        let viewModel = makeViewModel(now: now)

        let day = try #require(viewModel.days.first { $0.isInDisplayedMonth })

        #expect((0...1).contains(day.moon.illuminatedFraction))
        // A semidiurnal M2-only location has roughly two highs and two lows a day.
        #expect(day.highs.count >= 1)
        #expect(day.lows.count >= 1)
        #expect(day.highs.allSatisfy { $0.time >= day.date })
        // Tokyo has a sunrise and a sunset on every day of the year.
        let sunrise = try #require(day.sunrise)
        let sunset = try #require(day.sunset)
        #expect(sunrise < sunset)
        #expect(calendar.isDate(sunrise, inSameDayAs: day.date))
    }

    /// Recomputing the grid (e.g. switching the datum) keeps the selected day.
    @Test
    func reloadKeepsTheSelectedDay() async throws {
        let now = Date(timeIntervalSince1970: 1_767_225_600)
        let viewModel = TideCalendarViewModel(
            parameters: makeParameters(),
            latitude: 35.6762,
            longitude: 139.6503,
            datum: .chartDatum,
            calendar: calendar,
            now: now
        )
        let target = try #require(viewModel.days.first { $0.isInDisplayedMonth && $0.dayOfMonth == 15 })
        viewModel.selectedDay = target

        viewModel.setDatum(.meanSeaLevel)
        await viewModel.reloadTask?.value

        let selected = try #require(viewModel.selectedDay)
        #expect(calendar.isDate(selected.date, inSameDayAs: target.date))
    }

    @Test
    func monthNavigationMovesTheGrid() {
        let now = Date(timeIntervalSince1970: 1_767_225_600)
        let viewModel = makeViewModel(now: now)
        let january = viewModel.monthStart

        viewModel.goToNextMonth()
        #expect(calendar.component(.month, from: viewModel.monthStart) == 2)
        #expect(!viewModel.isShowingCurrentMonth || calendar.isDate(viewModel.monthStart, equalTo: .now, toGranularity: .month))

        viewModel.goToPreviousMonth()
        #expect(viewModel.monthStart == january)
    }

    private func makeViewModel(now: Date, initialDate: Date?) -> TideCalendarViewModel {
        TideCalendarViewModel(
            parameters: makeParameters(),
            latitude: 35.6762,
            longitude: 139.6503,
            calendar: calendar,
            now: now,
            initialDate: initialDate
        )
    }

    /// Opening on an explicit date shows that date's month, not the current one.
    @Test
    func initialDateOpensOnItsOwnMonth() throws {
        let now = Date(timeIntervalSince1970: 1_767_225_600)  // 2026-01-01, JST
        let march15 = Date(timeIntervalSince1970: 1_773_543_600)  // 2026-03-15 12:00 JST
        let viewModel = makeViewModel(now: now, initialDate: march15)

        // 2026-03-01 00:00 JST — the month the initial date falls in, not now's.
        #expect(viewModel.monthStart == Date(timeIntervalSince1970: 1_772_290_800))
        #expect(viewModel.days.filter(\.isInDisplayedMonth).count == 31)

        let selected = try #require(viewModel.selectedDay)
        #expect(selected.dayOfMonth == 15)
        #expect(selected.isInDisplayedMonth)
        // Today is in January, so no cell of the March grid is today.
        #expect(!viewModel.days.contains { $0.isToday && $0.isInDisplayedMonth })
    }

    /// Within the current month the explicit date wins over today, which is
    /// the fallback `updateSelection` uses when nothing is preferred.
    @Test
    func initialDateIsPreferredOverToday() throws {
        let now = Date(timeIntervalSince1970: 1_767_225_600)  // 2026-01-01, JST
        let january20 = Date(timeIntervalSince1970: 1_768_878_000)  // 2026-01-20 12:00 JST
        let viewModel = makeViewModel(now: now, initialDate: january20)

        #expect(calendar.component(.month, from: viewModel.monthStart) == 1)

        let selected = try #require(viewModel.selectedDay)
        #expect(selected.dayOfMonth == 20)
        #expect(!selected.isToday)
        // Today is still marked in the grid — it just is not the selection.
        #expect(viewModel.days.contains { $0.isToday && $0.dayOfMonth == 1 })
    }

    /// The month and day come from the calendar's time zone, not UTC. This
    /// instant is 2026-03-31 in UTC but already 2026-04-01 in Tokyo, so the
    /// calendar must open on April.
    @Test
    func initialDateResolvesTheMonthInTheCalendarsTimeZone() throws {
        let now = Date(timeIntervalSince1970: 1_767_225_600)
        // 2026-03-31T15:30:00Z == 2026-04-01 00:30 JST
        let acrossMidnight = Date(timeIntervalSince1970: 1_774_971_000)
        let viewModel = makeViewModel(now: now, initialDate: acrossMidnight)

        #expect(calendar.component(.month, from: viewModel.monthStart) == 4)

        let selected = try #require(viewModel.selectedDay)
        #expect(selected.dayOfMonth == 1)
        #expect(selected.isInDisplayedMonth)
    }

    /// Without an explicit date the calendar still opens on today.
    @Test
    func withoutAnInitialDateTheCalendarOpensOnToday() throws {
        let now = Date(timeIntervalSince1970: 1_767_225_600)  // 2026-01-01, JST
        let viewModel = makeViewModel(now: now, initialDate: nil)

        #expect(calendar.component(.month, from: viewModel.monthStart) == 1)

        let selected = try #require(viewModel.selectedDay)
        #expect(selected.isToday)
        #expect(selected.dayOfMonth == 1)
    }
}

// MARK: - Reordering

@MainActor
struct SavedLocationOrderingTests {
    private func makeLocations(_ names: [String]) throws -> [SavedLocation] {
        try names.enumerated().map { index, name in
            try SavedLocation(
                name: name,
                latitude: 35.0 + Double(index),
                longitude: 139.0,
                parameters: makeParameters(),
                sortOrder: index
            )
        }
    }

    /// Dragging a row down renumbers every affected row, so the order survives
    /// a relaunch (the list is queried by sortOrder).
    @Test
    func movingARowDownRenumbersTheList() throws {
        let locations = try makeLocations(["A", "B", "C", "D"])

        SavedLocation.move(locations, fromOffsets: IndexSet(integer: 0), toOffset: 3)

        let ordered = locations.sorted { $0.sortOrder < $1.sortOrder }
        #expect(ordered.map(\.name) == ["B", "C", "A", "D"])
        #expect(ordered.map(\.sortOrder) == [0, 1, 2, 3])
    }

    @Test
    func movingARowUpRenumbersTheList() throws {
        let locations = try makeLocations(["A", "B", "C", "D"])

        SavedLocation.move(locations, fromOffsets: IndexSet(integer: 3), toOffset: 1)

        let ordered = locations.sorted { $0.sortOrder < $1.sortOrder }
        #expect(ordered.map(\.name) == ["A", "D", "B", "C"])
        #expect(ordered.map(\.sortOrder) == [0, 1, 2, 3])
    }

    @Test
    func movingMultipleRowsKeepsTheirRelativeOrder() throws {
        let locations = try makeLocations(["A", "B", "C", "D"])

        SavedLocation.move(locations, fromOffsets: IndexSet([0, 2]), toOffset: 4)

        let ordered = locations.sorted { $0.sortOrder < $1.sortOrder }
        #expect(ordered.map(\.name) == ["B", "D", "A", "C"])
    }

    /// Stores written before reordering existed have every sortOrder at the
    /// default 0; the first drag must still produce a contiguous order.
    @Test
    func renumberingRepairsALegacyStoreWhereEveryOrderIsZero() throws {
        let locations = try makeLocations(["A", "B", "C"])
        for location in locations {
            location.sortOrder = 0
        }

        SavedLocation.renumber(locations)

        #expect(locations.map(\.sortOrder) == [0, 1, 2])
    }

    /// A new location is appended, never dropped into the middle of the order.
    @Test
    func newLocationsAreAppended() throws {
        let locations = try makeLocations(["A", "B", "C"])

        #expect(SavedLocation.nextSortOrder(after: locations) == 3)
        #expect(SavedLocation.nextSortOrder(after: []) == 0)
    }
}
