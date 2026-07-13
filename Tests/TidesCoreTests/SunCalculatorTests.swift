import Foundation
import Testing
import TidesCore

/// Checks `SunCalculator` against published sunrise/sunset times (NAOJ for
/// Tokyo, NOAA's solar calculator elsewhere). The algorithm is good to well
/// under a minute; the tolerance leaves room for rounding in the references.
struct SunCalculatorTests {
    private let toleranceSeconds: TimeInterval = 180

    private func calendar(_ identifier: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: identifier) ?? .gmt
        return calendar
    }

    /// Parses "yyyy-MM-dd HH:mm" in the calendar's time zone.
    private func date(_ string: String, in calendar: Calendar) -> Date {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.date(from: string) ?? .distantPast
    }

    @Test
    func tokyoNewYearsDay() throws {
        let calendar = calendar("Asia/Tokyo")
        let day = SunCalculator.day(
            containing: date("2026-01-01 12:00", in: calendar),
            latitude: 35.6762,
            longitude: 139.6503,
            calendar: calendar
        )
        let sunrise = try #require(day.sunrise)
        let sunset = try #require(day.sunset)
        // NAOJ Tokyo: sunrise 6:51, sunset 16:38.
        #expect(abs(sunrise.timeIntervalSince(date("2026-01-01 06:51", in: calendar))) < toleranceSeconds)
        #expect(abs(sunset.timeIntervalSince(date("2026-01-01 16:38", in: calendar))) < toleranceSeconds)
    }

    @Test
    func tokyoJuneSolstice() throws {
        let calendar = calendar("Asia/Tokyo")
        let day = SunCalculator.day(
            containing: date("2026-06-21 12:00", in: calendar),
            latitude: 35.6762,
            longitude: 139.6503,
            calendar: calendar
        )
        let sunrise = try #require(day.sunrise)
        let sunset = try #require(day.sunset)
        // NAOJ Tokyo: sunrise 4:25, sunset 19:00.
        #expect(abs(sunrise.timeIntervalSince(date("2026-06-21 04:25", in: calendar))) < toleranceSeconds)
        #expect(abs(sunset.timeIntervalSince(date("2026-06-21 19:00", in: calendar))) < toleranceSeconds)
    }

    /// Southern hemisphere, and a time zone far from the location's mean
    /// solar time (daylight saving in effect).
    @Test
    func sydneyNewYearsDay() throws {
        let calendar = calendar("Australia/Sydney")
        let day = SunCalculator.day(
            containing: date("2026-01-01 12:00", in: calendar),
            latitude: -33.8688,
            longitude: 151.2093,
            calendar: calendar
        )
        let sunrise = try #require(day.sunrise)
        let sunset = try #require(day.sunset)
        // NOAA: sunrise 5:49, sunset 20:09 AEDT.
        #expect(abs(sunrise.timeIntervalSince(date("2026-01-01 05:49", in: calendar))) < 300)
        #expect(abs(sunset.timeIntervalSince(date("2026-01-01 20:09", in: calendar))) < 300)
    }

    @Test
    func polarNightAndMidnightSun() {
        let calendar = calendar("Arctic/Longyearbyen")
        // Longyearbyen, Svalbard (78.22° N).
        let winter = SunCalculator.day(
            containing: date("2026-01-01 12:00", in: calendar),
            latitude: 78.2232,
            longitude: 15.6267,
            calendar: calendar
        )
        #expect(winter == .alwaysDown)

        let summer = SunCalculator.day(
            containing: date("2026-06-21 12:00", in: calendar),
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
        let calendar = calendar("Asia/Tokyo")
        let lateNight = date("2026-03-15 23:55", in: calendar)
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
}
