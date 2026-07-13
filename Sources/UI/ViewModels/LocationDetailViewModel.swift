import Foundation
import Observation
import TidesCore

/// View model for the tide detail screen. All computation is local via
/// `TidePredictor` — no network access is needed once parameters are saved.
@MainActor
@Observable
final class LocationDetailViewModel {
    /// A high or low water event for display.
    struct ExtremumItem: Identifiable, Equatable {
        enum Kind { case high, low }
        var kind: Kind
        var time: Date
        var heightMeters: Double
        var id: Date { time }
    }

    private(set) var parameters: HarmonicParameters
    /// Datum the displayed heights are measured from.
    private(set) var datum: TideDatum
    private var predictor: TidePredictor
    private let calendar: Calendar
    /// Coordinate the sun times are computed for. Updated by `replace` when
    /// the location is moved.
    private var latitude: Double
    private var longitude: Double

    /// Start of the currently displayed day.
    private(set) var dayStart: Date
    /// 30-minute tide curve covering the displayed day and the next day.
    private(set) var levels: [TideLevel] = []
    /// Highs and lows in the displayed window, sorted by time.
    private(set) var extrema: [ExtremumItem] = []
    /// Tide height right now.
    private(set) var currentHeightMeters: Double?
    /// Daylight periods within the displayed window, in chronological order.
    /// The chart darkens everything outside them.
    private(set) var daylight: [DateInterval] = []
    /// Sunrise of the displayed day, or `nil` on polar days.
    private(set) var sunrise: Date?
    /// Sunset of the displayed day, or `nil` on polar days.
    private(set) var sunset: Date?

    /// Chart interval: the displayed day plus the following day.
    var windowStart: Date { dayStart }
    var windowEnd: Date { calendar.date(byAdding: .day, value: 2, to: dayStart) ?? dayStart }

    /// When `reload` last ran, so a re-appearing view can refresh "now"
    /// without duplicating the load the initializer already did.
    private var reloadedAt: Date = .distantPast

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
        self.dayStart = calendar.startOfDay(for: now)
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
        levels = predictor.predictions(from: windowStart, to: windowEnd, interval: 30 * 60)
        let result = predictor.extrema(from: windowStart, to: windowEnd)
        extrema = (
            result.highs.map { ExtremumItem(kind: .high, time: $0.time, heightMeters: $0.heightMeters) }
                + result.lows.map { ExtremumItem(kind: .low, time: $0.time, heightMeters: $0.heightMeters) }
        )
        .sorted { $0.time < $1.time }
        currentHeightMeters = predictor.height(at: now)
        reloadSun()
        reloadedAt = now
    }

    /// Recomputes the daylight periods and the displayed day's sun times.
    private func reloadSun() {
        var daylight: [DateInterval] = []
        sunrise = nil
        sunset = nil
        var day = windowStart
        while day < windowEnd {
            let dayEnd = calendar.date(byAdding: .day, value: 1, to: day) ?? windowEnd
            switch SunCalculator.day(
                containing: day,
                latitude: latitude,
                longitude: longitude,
                calendar: calendar
            ) {
            case let .risesAndSets(rise, set):
                daylight.append(DateInterval(start: rise, end: set))
                if day == windowStart {
                    sunrise = rise
                    sunset = set
                }
            case .alwaysUp:
                daylight.append(DateInterval(start: day, end: dayEnd))
            case .alwaysDown:
                break
            }
            day = dayEnd
        }
        self.daylight = daylight
    }

    /// Night periods within the displayed window — the complement of
    /// `daylight`, which the chart shades dark.
    var nightIntervals: [DateInterval] {
        var night: [DateInterval] = []
        var cursor = windowStart
        for interval in daylight where interval.end > cursor {
            if interval.start > cursor {
                night.append(DateInterval(start: cursor, end: min(interval.start, windowEnd)))
            }
            cursor = interval.end
        }
        if cursor < windowEnd {
            night.append(DateInterval(start: cursor, end: windowEnd))
        }
        return night
    }

    /// True when the displayed day is today (used to disable the Today button).
    var isShowingToday: Bool {
        calendar.isDate(dayStart, inSameDayAs: .now)
    }

    func goToToday(now: Date = .now) {
        dayStart = calendar.startOfDay(for: now)
        reload(now: now)
    }

    func goToPreviousDay() {
        step(days: -1)
    }

    func goToNextDay() {
        step(days: 1)
    }

    /// Sets the displayed day from a date picker value.
    func setDay(_ date: Date) {
        let newStart = calendar.startOfDay(for: date)
        guard newStart != dayStart else { return }
        dayStart = newStart
        reload()
    }

    private func step(days: Int) {
        guard let next = calendar.date(byAdding: .day, value: days, to: dayStart) else { return }
        dayStart = next
        reload()
    }
}
