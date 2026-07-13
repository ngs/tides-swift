import Foundation
import Observation
import TidesCore

/// View model for the month calendar: one cell per day with the Moon's phase
/// and that day's high and low waters, all computed offline.
@MainActor
@Observable
public final class TideCalendarViewModel {
    /// One day of the displayed month grid.
    public struct Day: Identifiable, Equatable {
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

    public init(
        parameters: HarmonicParameters,
        datum: TideDatum = TideDatumSettings.current,
        calendar: Calendar = .current,
        now: Date = .now
    ) {
        self.parameters = parameters
        self.datum = datum
        self.predictor = TidePredictor(parameters: parameters, datum: datum)
        self.calendar = calendar
        self.monthStart = calendar.startOfMonth(for: now)
        reload(now: now)
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

    /// Rebuilds the grid: whole weeks covering the month, each day carrying its
    /// Moon phase and tide extrema.
    private func reload(now: Date = .now) {
        guard
            let monthRange = calendar.range(of: .day, in: .month, for: monthStart),
            let gridStart = calendar.startOfWeekContaining(monthStart)
        else {
            days = []
            return
        }

        // Whole weeks: pad to cover the last day of the month.
        let dayCount = monthRange.count
        let lastDay = calendar.date(byAdding: .day, value: dayCount - 1, to: monthStart) ?? monthStart
        let gridEnd = calendar.date(byAdding: .day, value: 7, to: calendar.startOfWeekContaining(lastDay) ?? lastDay)
            ?? lastDay
        let totalDays = calendar.dateComponents([.day], from: gridStart, to: gridEnd).day ?? 42

        days = (0..<totalDays).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset, to: gridStart) else {
                return nil
            }
            return makeDay(date: date, now: now)
        }

        // Keep a selection so the list under the grid is never empty.
        let today = days.first { $0.isToday && $0.isInDisplayedMonth }
        selectedDay = today ?? days.first { $0.isInDisplayedMonth }
    }

    private func makeDay(date: Date, now: Date) -> Day {
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
