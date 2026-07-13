import Foundation
import Testing
import TidesCore

/// Checks `SunCalculator` against published sunrise/sunset times (NAOJ for
/// Tokyo, NOAA's solar calculator elsewhere). The algorithm is good to well
/// under a minute; the tolerance leaves room for rounding in the references.
struct SunCalculatorTests {
    private let toleranceSeconds: TimeInterval = 180

    private func calendar(_ identifier: String) throws -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: identifier))
        return calendar
    }

    /// Parses "yyyy-MM-dd HH:mm" in the calendar's time zone.
    private func date(_ string: String, in calendar: Calendar) throws -> Date {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return try #require(formatter.date(from: string))
    }

    @Test
    func tokyoNewYearsDay() throws {
        let calendar = try calendar("Asia/Tokyo")
        let day = SunCalculator.day(
            containing: try date("2026-01-01 12:00", in: calendar),
            latitude: 35.6762,
            longitude: 139.6503,
            calendar: calendar
        )
        let sunrise = try #require(day.sunrise)
        let sunset = try #require(day.sunset)
        // NAOJ Tokyo: sunrise 6:51, sunset 16:38.
        #expect(abs(sunrise.timeIntervalSince(try date("2026-01-01 06:51", in: calendar))) < toleranceSeconds)
        #expect(abs(sunset.timeIntervalSince(try date("2026-01-01 16:38", in: calendar))) < toleranceSeconds)
    }

    @Test
    func tokyoJuneSolstice() throws {
        let calendar = try calendar("Asia/Tokyo")
        let day = SunCalculator.day(
            containing: try date("2026-06-21 12:00", in: calendar),
            latitude: 35.6762,
            longitude: 139.6503,
            calendar: calendar
        )
        let sunrise = try #require(day.sunrise)
        let sunset = try #require(day.sunset)
        // NAOJ Tokyo: sunrise 4:25, sunset 19:00.
        #expect(abs(sunrise.timeIntervalSince(try date("2026-06-21 04:25", in: calendar))) < toleranceSeconds)
        #expect(abs(sunset.timeIntervalSince(try date("2026-06-21 19:00", in: calendar))) < toleranceSeconds)
    }

    /// Southern hemisphere, and a time zone far from the location's mean
    /// solar time (daylight saving in effect).
    @Test
    func sydneyNewYearsDay() throws {
        let calendar = try calendar("Australia/Sydney")
        let day = SunCalculator.day(
            containing: try date("2026-01-01 12:00", in: calendar),
            latitude: -33.8688,
            longitude: 151.2093,
            calendar: calendar
        )
        let sunrise = try #require(day.sunrise)
        let sunset = try #require(day.sunset)
        // NOAA: sunrise 5:49, sunset 20:09 AEDT.
        #expect(abs(sunrise.timeIntervalSince(try date("2026-01-01 05:49", in: calendar))) < 300)
        #expect(abs(sunset.timeIntervalSince(try date("2026-01-01 20:09", in: calendar))) < 300)
    }

    @Test
    func polarNightAndMidnightSun() throws {
        let calendar = try calendar("Arctic/Longyearbyen")
        // Longyearbyen, Svalbard (78.22° N).
        let winter = SunCalculator.day(
            containing: try date("2026-01-01 12:00", in: calendar),
            latitude: 78.2232,
            longitude: 15.6267,
            calendar: calendar
        )
        #expect(winter == .alwaysDown)

        let summer = SunCalculator.day(
            containing: try date("2026-06-21 12:00", in: calendar),
            latitude: 78.2232,
            longitude: 15.6267,
            calendar: calendar
        )
        #expect(summer == .alwaysUp)
    }

    /// The sunrise must fall inside the requested civil day even when the
    /// query instant is close to midnight.
    @Test
    func eventsStayWithinTheRequestedDay() throws {
        let calendar = try calendar("Asia/Tokyo")
        let lateNight = try date("2026-03-15 23:55", in: calendar)
        let day = SunCalculator.day(
            containing: lateNight,
            latitude: 35.6762,
            longitude: 139.6503,
            calendar: calendar
        )
        let sunrise = try #require(day.sunrise)
        let sunset = try #require(day.sunset)
        let dayStart = calendar.startOfDay(for: lateNight)
        let dayEnd = dayStart.addingTimeInterval(86_400)
        #expect((dayStart..<dayEnd).contains(sunrise))
        #expect((dayStart..<dayEnd).contains(sunset))
        #expect(sunrise < sunset)
    }

    /// A 23-hour civil day: the US spring-forward date. The transit estimate
    /// starts from the day's midpoint, so the events must stay in the day.
    @Test
    func daylightSavingTransitionDayStaysConsistent() throws {
        let calendar = try calendar("America/New_York")
        let springForward = try date("2026-03-08 01:30", in: calendar)
        let day = SunCalculator.day(
            containing: springForward,
            latitude: 40.7128,
            longitude: -74.0060,
            calendar: calendar
        )
        let sunrise = try #require(day.sunrise)
        let sunset = try #require(day.sunset)
        let dayStart = calendar.startOfDay(for: springForward)
        let dayEnd = try #require(calendar.date(byAdding: .day, value: 1, to: dayStart))
        // The day is only 23 hours long.
        #expect(dayEnd.timeIntervalSince(dayStart) == 23 * 3_600)
        #expect((dayStart..<dayEnd).contains(sunrise))
        #expect((dayStart..<dayEnd).contains(sunset))
        #expect(sunrise < sunset)
    }
}
