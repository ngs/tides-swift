import Foundation
import Observation
import TidesCore

/// View model for the month calendar: one cell per day with the Moon's phase
/// and that day's high and low waters, all computed offline.
@MainActor
@Observable
public final class TideCalendarViewModel {
    /// One day of the displayed month grid.
    public struct Day: Identifiable, Equatable, Sendable {
        public let date: Date
        public let dayOfMonth: Int
        /// False for the leading/trailing days that pad the grid to whole weeks.
        public let isInDisplayedMonth: Bool
        public let isToday: Bool
        /// The Moon at local noon, which is what a calendar icon represents.
        public let moon: MoonPhase
        public let highs: [TideLevel]
        public let lows: [TideLevel]

        public var id: Date { date }
    }

    private var predictor: TidePredictor
    private let parameters: HarmonicParameters
    /// Datum the displayed heights are measured from.
    private var datum: TideDatum
    private let calendar: Calendar

    /// First day of the displayed month.
    public private(set) var monthStart: Date
    public private(set) var days: [Day] = []
    /// Day whose tides are listed below the grid.
    public var selectedDay: Day?
    /// In-flight background rebuild of `days`, if any. Tests await it; views
    /// simply observe `days` updating when it finishes.
    public private(set) var reloadTask: Task<Void, Never>?

    public init(
        parameters: HarmonicParameters,
        datum: TideDatum = TideDatumSettings.current,
        calendar: Calendar = .current,
        now: Date = .now
    ) {
        self.parameters = parameters
        self.datum = datum
        let predictor = TidePredictor(parameters: parameters, datum: datum)
        self.predictor = predictor
        self.calendar = calendar
        let monthStart = calendar.startOfMonth(for: now)
        self.monthStart = monthStart
        // The first grid is computed synchronously so the view never appears
        // empty; later rebuilds happen off the main actor in `reload`.
        self.days = Self.makeDays(monthStart: monthStart, predictor: predictor, calendar: calendar, now: now)
        updateSelection()
    }

    /// Switches the datum the heights are displayed against and recomputes.
    public func setDatum(_ newDatum: TideDatum) {
        guard newDatum != datum else { return }
        datum = newDatum
        predictor = TidePredictor(parameters: parameters, datum: newDatum)
        reload()
    }

    /// Localized one-letter/short weekday symbols in the calendar's first-weekday
    /// order, for the grid header.
    public var weekdaySymbols: [String] {
        let symbols = calendar.shortWeekdaySymbols
        let first = calendar.firstWeekday - 1
        return Array(symbols[first...] + symbols[..<first])
    }

    public var monthTitle: Date { monthStart }

    public func goToPreviousMonth() {
        step(months: -1)
    }

    public func goToNextMonth() {
        step(months: 1)
    }

    public func goToToday(now: Date = .now) {
        monthStart = calendar.startOfMonth(for: now)
        reload(now: now)
    }

    public var isShowingCurrentMonth: Bool {
        calendar.isDate(monthStart, equalTo: .now, toGranularity: .month)
    }

    private func step(months: Int) {
        guard let next = calendar.date(byAdding: .month, value: months, to: monthStart) else {
            return
        }
        monthStart = next
        reload()
    }

    /// Rebuilds the grid off the main actor: a month of extrema is a lot of
    /// harmonic evaluations, too heavy to run synchronously on the main
    /// thread when paging months or switching the datum.
    private func reload(now: Date = .now) {
        reloadTask?.cancel()
        let monthStart = monthStart
        let predictor = predictor
        let calendar = calendar
        reloadTask = Task { [weak self] in
            let days = await Task.detached(priority: .userInitiated) {
                Self.makeDays(monthStart: monthStart, predictor: predictor, calendar: calendar, now: now)
            }.value
            guard let self, !Task.isCancelled else { return }
            self.days = days
            self.updateSelection()
        }
    }

    /// Keeps the user's selection when the rebuilt grid still shows that day;
    /// otherwise falls back so the list under the grid is never empty.
    private func updateSelection() {
        let previousDate = selectedDay?.date
        let preserved = previousDate.flatMap { date in
            days.first { $0.isInDisplayedMonth && calendar.isDate($0.date, inSameDayAs: date) }
        }
        let today = days.first { $0.isToday && $0.isInDisplayedMonth }
        selectedDay = preserved ?? today ?? days.first { $0.isInDisplayedMonth }
    }

    /// Whole weeks covering the month, each day carrying its Moon phase and
    /// tide extrema. Pure, so `reload` can run it off the main actor.
    nonisolated private static func makeDays(
        monthStart: Date,
        predictor: TidePredictor,
        calendar: Calendar,
        now: Date
    ) -> [Day] {
        guard
            let monthRange = calendar.range(of: .day, in: .month, for: monthStart),
            let gridStart = calendar.startOfWeekContaining(monthStart)
        else {
            return []
        }

        // Whole weeks: pad to cover the last day of the month.
        let dayCount = monthRange.count
        let lastDay = calendar.date(byAdding: .day, value: dayCount - 1, to: monthStart) ?? monthStart
        let gridEnd = calendar.date(byAdding: .day, value: 7, to: calendar.startOfWeekContaining(lastDay) ?? lastDay)
            ?? lastDay
        let totalDays = calendar.dateComponents([.day], from: gridStart, to: gridEnd).day ?? 42

        return (0..<totalDays).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset, to: gridStart) else {
                return nil
            }
            return makeDay(date: date, monthStart: monthStart, predictor: predictor, calendar: calendar, now: now)
        }
    }

    nonisolated private static func makeDay(
        date: Date,
        monthStart: Date,
        predictor: TidePredictor,
        calendar: Calendar,
        now: Date
    ) -> Day {
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: date) ?? date
        let extrema = predictor.extrema(from: date, to: dayEnd)
        // Noon: the phase a calendar cell stands for, rather than midnight.
        let noon = calendar.date(byAdding: .hour, value: 12, to: date) ?? date

        return Day(
            date: date,
            dayOfMonth: calendar.component(.day, from: date),
            isInDisplayedMonth: calendar.isDate(date, equalTo: monthStart, toGranularity: .month),
            isToday: calendar.isDate(date, inSameDayAs: now),
            moon: MoonPhase(date: noon),
            highs: extrema.highs,
            lows: extrema.lows
        )
    }
}

extension Calendar {
    /// Midnight on the first day of the month containing `date`.
    func startOfMonth(for date: Date) -> Date {
        self.date(from: dateComponents([.year, .month], from: date)) ?? startOfDay(for: date)
    }

    /// Midnight on the first day of the week containing `date`.
    func startOfWeekContaining(_ date: Date) -> Date? {
        dateInterval(of: .weekOfMonth, for: date)?.start
    }
}
