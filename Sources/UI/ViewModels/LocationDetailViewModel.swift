import Foundation
import Observation
import TidesCore

/// View model for the tide detail screen. All computation is local via
/// `TidePredictor` — no network access is needed once parameters are saved.
@MainActor
@Observable
final class LocationDetailViewModel {
    /// A high or low water event for display.
    nonisolated struct ExtremumItem: Identifiable, Equatable, Sendable {
        enum Kind { case high, low }
        var kind: Kind
        var time: Date
        var heightMeters: Double
        var id: Date { time }
    }

    /// A sunrise or sunset, positioned under the chart at its time.
    nonisolated struct SunEvent: Identifiable, Equatable, Sendable {
        enum Kind { case sunrise, sunset }
        var kind: Kind
        var time: Date
        var id: Date { time }
    }

    /// Everything recomputed when the pannable range changes, grouped so the
    /// computation can run off the main actor when the range grows mid-pan.
    nonisolated private struct RangeData: Sendable {
        var levels: [TideLevel]
        var extrema: [ExtremumItem]
        var daylight: [DateInterval]
        var sunEvents: [SunEvent]
    }

    /// The inputs `rangeData` needs, bundled so the computation can be
    /// handed to a background task as one value.
    nonisolated private struct RangeRequest: Sendable {
        var predictor: TidePredictor
        var start: Date
        var end: Date
        var latitude: Double
        var longitude: Double
        var calendar: Calendar
    }

    /// Days of predictions kept on each side of the visible window, and the
    /// increment the range grows by when panning approaches an edge.
    private static let bufferDays = 7

    private(set) var parameters: HarmonicParameters
    /// Datum the displayed heights are measured from.
    private(set) var datum: TideDatum
    private var predictor: TidePredictor
    private let calendar: Calendar
    /// Coordinate the sun times are computed for. Updated by `replace` when
    /// the location is moved.
    private var latitude: Double
    private var longitude: Double

    /// The instant at the chart's center — the scrubbing cursor. Panning the
    /// chart moves it continuously; it starts at "now".
    private(set) var centerDate: Date
    /// Start of the computed prediction range the chart can pan through.
    /// Grows as the user pans towards an edge.
    private(set) var rangeStart: Date
    /// End of the computed prediction range.
    private(set) var rangeEnd: Date
    /// 30-minute tide curve covering the whole pannable range.
    private(set) var levels: [TideLevel] = []
    /// Highs and lows across the pannable range, sorted by time.
    private(set) var extrema: [ExtremumItem] = []
    /// Tide height right now (the red "Now" marker).
    private(set) var currentHeightMeters: Double?
    /// Daylight periods within the pannable range, in chronological order.
    /// The chart darkens everything outside them.
    private(set) var daylight: [DateInterval] = []
    /// Sunrises and sunsets within the pannable range, sorted by time.
    private(set) var sunEvents: [SunEvent] = []

    /// Visible chart interval: one day either side of the center.
    var windowStart: Date { centerDate.addingTimeInterval(-86_400) }
    var windowEnd: Date { centerDate.addingTimeInterval(86_400) }

    /// When `reload` last ran, so a re-appearing view can refresh "now"
    /// without duplicating the load the initializer already did.
    private var reloadedAt: Date = .distantPast

    /// In-flight background range extension, if any. At most one runs at a
    /// time; the next pan retriggers the check.
    private var extensionTask: Task<Void, Never>?
    /// Bumped by every synchronous `reload` so a background extension that
    /// raced it throws its stale result away.
    private var generation = 0

    init(
        parameters: HarmonicParameters,
        latitude: Double,
        longitude: Double,
        datum: TideDatum = TideDatumSettings.current,
        calendar: Calendar = .current,
        now: Date = .now
    ) {
        self.parameters = parameters
        self.latitude = latitude
        self.longitude = longitude
        self.datum = datum
        self.predictor = TidePredictor(parameters: parameters, datum: datum)
        self.calendar = calendar
        self.centerDate = now
        let dayStart = calendar.startOfDay(for: now)
        self.rangeStart = calendar.date(byAdding: .day, value: -Self.bufferDays, to: dayStart) ?? dayStart
        self.rangeEnd = calendar.date(byAdding: .day, value: Self.bufferDays + 1, to: dayStart) ?? dayStart
        reload()
    }

    /// Swaps in parameters downloaded for a new coordinate (the location was
    /// moved) and recomputes the displayed window, sun times included.
    func replace(
        parameters newParameters: HarmonicParameters,
        latitude newLatitude: Double,
        longitude newLongitude: Double
    ) {
        guard
            newParameters != parameters
                || newLatitude != latitude
                || newLongitude != longitude
        else { return }
        parameters = newParameters
        latitude = newLatitude
        longitude = newLongitude
        predictor = TidePredictor(parameters: newParameters, datum: datum)
        reload()
    }

    /// Switches the datum the heights are displayed against and recomputes.
    func setDatum(_ newDatum: TideDatum) {
        guard newDatum != datum else { return }
        datum = newDatum
        predictor = TidePredictor(parameters: parameters, datum: newDatum)
        reload()
    }

    /// Recomputes only when the last computation is old enough for "now" to
    /// have moved visibly. Keeps `onAppear` from repeating the work the
    /// initializer (or a datum switch) just did.
    func reloadIfStale(now: Date = .now) {
        guard now.timeIntervalSince(reloadedAt) >= 60 else { return }
        reload(now: now)
    }

    func reload(now: Date = .now) {
        generation += 1
        apply(Self.rangeData(for: rangeRequest(from: rangeStart, to: rangeEnd)))
        currentHeightMeters = predictor.height(at: now)
        reloadedAt = now
    }

    private func rangeRequest(from start: Date, to end: Date) -> RangeRequest {
        RangeRequest(
            predictor: predictor,
            start: start,
            end: end,
            latitude: latitude,
            longitude: longitude,
            calendar: calendar
        )
    }

    /// Tide height at an arbitrary instant, for the scrubbed center readout.
    /// A single harmonic sum — cheap enough to call every pan frame.
    func height(at date: Date) -> Double {
        predictor.height(at: date)
    }

    /// Shifts the center by a settled pan and extends the range when needed.
    func pan(bySeconds seconds: TimeInterval) {
        guard seconds != 0 else { return }
        centerDate = centerDate.addingTimeInterval(seconds)
        extendRangeIfNeeded()
    }

    /// Steps the center by whole days (the chevron buttons).
    func step(byDays days: Int) {
        guard let next = calendar.date(byAdding: .day, value: days, to: centerDate) else { return }
        centerDate = next
        extendRangeIfNeeded()
    }

    /// Recenters on the present moment.
    func goToNow(now: Date = .now) {
        centerDate = now
        currentHeightMeters = predictor.height(at: now)
        extendRangeIfNeeded()
    }

    /// Grows the computed range when the visible window gets within two days
    /// of an edge, so panning never runs out of data. The recomputation runs
    /// off the main actor: a pan settles without a hitch, and the wider data
    /// is swapped in when ready (the clamp in the view keeps the visible
    /// window inside the old range until then).
    private func extendRangeIfNeeded() {
        guard extensionTask == nil else { return }
        var newStart = rangeStart
        var newEnd = rangeEnd
        if let lowWatermark = calendar.date(byAdding: .day, value: 2, to: rangeStart),
           windowStart < lowWatermark,
           let extended = calendar.date(byAdding: .day, value: -Self.bufferDays, to: rangeStart) {
            newStart = extended
        }
        if let highWatermark = calendar.date(byAdding: .day, value: -2, to: rangeEnd),
           windowEnd > highWatermark,
           let extended = calendar.date(byAdding: .day, value: Self.bufferDays, to: rangeEnd) {
            newEnd = extended
        }
        guard newStart != rangeStart || newEnd != rangeEnd else { return }

        let expected = generation
        let request = rangeRequest(from: newStart, to: newEnd)
        extensionTask = Task { [weak self] in
            let data = await Self.computeRangeData(for: request)
            guard let self else { return }
            self.extensionTask = nil
            guard self.generation == expected else { return }
            self.rangeStart = newStart
            self.rangeEnd = newEnd
            self.apply(data)
        }
    }

    private func apply(_ data: RangeData) {
        levels = data.levels
        extrema = data.extrema
        daylight = data.daylight
        sunEvents = data.sunEvents
    }

    /// Off-main-actor wrapper around `rangeData` for background extension.
    nonisolated private static func computeRangeData(for request: RangeRequest) async -> RangeData {
        rangeData(for: request)
    }

    /// Predictions, extrema, daylight and sun events for a range. Pure —
    /// runs wherever it is called from.
    nonisolated private static func rangeData(for request: RangeRequest) -> RangeData {
        let predictor = request.predictor
        let start = request.start
        let end = request.end
        let calendar = request.calendar
        let levels = predictor.predictions(from: start, to: end, interval: 30 * 60)
        let result = predictor.extrema(from: start, to: end)
        let extrema = (
            result.highs.map { ExtremumItem(kind: .high, time: $0.time, heightMeters: $0.heightMeters) }
                + result.lows.map { ExtremumItem(kind: .low, time: $0.time, heightMeters: $0.heightMeters) }
        )
        .sorted { $0.time < $1.time }

        var daylight: [DateInterval] = []
        var sunEvents: [SunEvent] = []
        var day = start
        while day < end {
            let dayEnd = calendar.date(byAdding: .day, value: 1, to: day) ?? end
            switch SunCalculator.day(
                containing: day,
                latitude: request.latitude,
                longitude: request.longitude,
                calendar: calendar
            ) {
            case let .risesAndSets(rise, set):
                daylight.append(DateInterval(start: rise, end: set))
                sunEvents.append(SunEvent(kind: .sunrise, time: rise))
                sunEvents.append(SunEvent(kind: .sunset, time: set))
            case .alwaysUp:
                daylight.append(DateInterval(start: day, end: dayEnd))
            case .alwaysDown:
                break
            }
            day = dayEnd
        }
        return RangeData(levels: levels, extrema: extrema, daylight: daylight, sunEvents: sunEvents)
    }

    /// Night periods within the pannable range — the complement of
    /// `daylight`, which the chart shades dark.
    var nightIntervals: [DateInterval] {
        var night: [DateInterval] = []
        var cursor = rangeStart
        for interval in daylight where interval.end > cursor {
            if interval.start > cursor {
                night.append(DateInterval(start: cursor, end: min(interval.start, rangeEnd)))
            }
            cursor = interval.end
        }
        if cursor < rangeEnd {
            night.append(DateInterval(start: cursor, end: rangeEnd))
        }
        return night
    }

    /// Highs and lows within the visible window, for the list below the chart.
    var visibleExtrema: [ExtremumItem] {
        extrema.filter { (windowStart...windowEnd).contains($0.time) }
    }

    /// True when the chart is centered on the present moment, within a
    /// minute (used to disable the Now button).
    var isCenteredOnNow: Bool {
        abs(centerDate.timeIntervalSinceNow) < 60
    }
}
