import Foundation
import Testing
import TidesCore

/// The Moon–Sun elongation model is checked against published new and full moon
/// instants (UTC, from the USNO / IMCCE lunation tables). A calendar icon needs
/// no better than a few hours of accuracy, so the tolerances are stated in terms
/// of illuminated fraction and lunar age rather than minutes.
struct MoonPhaseTests {
    private static func date(_ iso: String) throws -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return try #require(formatter.date(from: iso), "unparseable date \(iso)")
    }

    /// Known new moons: the disc must be essentially dark and the age near zero
    /// (either just before the end of a lunation, or just after its start).
    @Test(arguments: [
        "2024-01-11T11:57:00Z",
        "2024-06-06T12:38:00Z",
        "2025-03-29T10:58:00Z",
        "2026-01-18T19:52:00Z"
    ])
    func newMoonsAreDark(iso: String) throws {
        let moon = MoonPhase(date: try Self.date(iso))

        #expect(moon.illuminatedFraction < 0.01, "\(iso): lit \(moon.illuminatedFraction)")

        let ageFromNew = min(moon.ageDays, MoonPhase.synodicMonthDays - moon.ageDays)
        #expect(ageFromNew < 0.35, "\(iso): age \(moon.ageDays)")
        #expect(moon.phase == .newMoon, "\(iso): phase \(moon.phase)")
    }

    /// Known full moons: the disc must be essentially lit and the age near half
    /// a lunation.
    @Test(arguments: [
        "2024-01-25T17:54:00Z",
        "2024-06-22T01:08:00Z",
        "2025-04-13T00:22:00Z",
        "2026-01-03T10:03:00Z"
    ])
    func fullMoonsAreLit(iso: String) throws {
        let moon = MoonPhase(date: try Self.date(iso))

        #expect(moon.illuminatedFraction > 0.99, "\(iso): lit \(moon.illuminatedFraction)")
        #expect(
            abs(moon.ageDays - MoonPhase.synodicMonthDays / 2) < 0.35,
            "\(iso): age \(moon.ageDays)"
        )
        #expect(moon.phase == .fullMoon, "\(iso): phase \(moon.phase)")
    }

    /// Quarters are half lit, and the waxing/waning flag distinguishes them.
    @Test
    func quartersAreHalfLit() throws {
        let first = MoonPhase(date: try Self.date("2024-01-18T03:53:00Z"))
        #expect(abs(first.illuminatedFraction - 0.5) < 0.02)
        #expect(first.isWaxing)
        #expect(first.phase == .firstQuarter)

        let last = MoonPhase(date: try Self.date("2024-02-02T23:18:00Z"))
        #expect(abs(last.illuminatedFraction - 0.5) < 0.02)
        #expect(!last.isWaxing)
        #expect(last.phase == .lastQuarter)
    }

    /// Age advances monotonically through a lunation, roughly a day per day.
    /// The rate is not exactly one: the Moon's elongation grows faster near
    /// perigee and slower near apogee, so the apparent age can advance by about
    /// 0.85 to 1.15 days in 24 hours.
    @Test
    func ageAdvancesMonotonicallyWithinALunation() throws {
        let start = try Self.date("2026-01-19T00:00:00Z")
        var previous = MoonPhase(date: start).ageDays

        for day in 1...25 {
            let moon = MoonPhase(date: start.addingTimeInterval(Double(day) * 86_400))
            let delta = moon.ageDays - previous
            #expect(delta > 0.8 && delta < 1.2, "day \(day): age advanced by \(delta)")
            previous = moon.ageDays
        }
    }

    /// Every instant must produce a usable icon and a fraction in range.
    @Test
    func allPhasesAreCoveredOverALunation() throws {
        let start = try Self.date("2026-01-18T19:52:00Z")
        var seen: Set<MoonPhase.Phase> = []

        // Sample every hour so the narrow exact-phase windows are hit.
        for hour in 0..<(30 * 24) {
            let moon = MoonPhase(date: start.addingTimeInterval(Double(hour) * 3_600))
            #expect((0...1).contains(moon.illuminatedFraction))
            #expect((0..<MoonPhase.synodicMonthDays).contains(moon.ageDays))
            #expect(!moon.phase.systemImageName.isEmpty)
            seen.insert(moon.phase)
        }

        #expect(seen.count == MoonPhase.Phase.allCases.count, "phases seen: \(seen)")
    }
}
