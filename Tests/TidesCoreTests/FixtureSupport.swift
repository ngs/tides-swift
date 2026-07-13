import Foundation
import Testing

enum FixtureSupport {
    /// Loads and decodes a JSON fixture from the test bundle resources.
    static func load<T: Decodable>(_ type: T.Type, fixture name: String) throws -> T {
        let bundle = Bundle.module
        let url = bundle.url(forResource: name, withExtension: "json", subdirectory: "Fixtures")
            ?? bundle.url(forResource: name, withExtension: "json")
        let fixtureURL = try #require(url, "fixture \(name).json not found in \(bundle.bundlePath)")
        let data = try Data(contentsOf: fixtureURL)
        return try JSONDecoder().decode(type, from: data)
    }

    /// Parses an RFC 3339 timestamp, with or without fractional seconds
    /// (Go's time.RFC3339Nano emits up to 9 fractional digits, which
    /// `ISO8601DateFormatter` does not reliably accept).
    static func date(rfc3339 string: String) throws -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]

        guard let dotIndex = string.firstIndex(of: ".") else {
            return try #require(formatter.date(from: string), "unparseable time \(string)")
        }

        // Split "2026-07-13T02:59:58.013273646Z" into a whole-second part
        // and a fractional part.
        let head = String(string[..<dotIndex])
        let tail = string[string.index(after: dotIndex)...]
        let fractionDigits = tail.prefix { $0.isNumber }
        let suffix = String(tail.dropFirst(fractionDigits.count)) // e.g. "Z"
        let base = try #require(
            formatter.date(from: head + suffix),
            "unparseable time \(string)"
        )
        let fraction = try #require(
            Double("0." + String(fractionDigits)),
            "unparseable fraction in \(string)"
        )
        return base.addingTimeInterval(fraction)
    }
}
