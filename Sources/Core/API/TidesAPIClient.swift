import Foundation

/// Abstraction over the tides-api network client so view models can be unit
/// tested with a mock.
public protocol TidesAPIClientProtocol: Sendable {
    /// Fetches harmonic constituent parameters for a coordinate.
    func fetchParameters(latitude: Double, longitude: Double) async throws -> HarmonicParameters
}

/// Error returned by tides-api (`{"error": "..."}` with a 4xx/5xx status).
public struct TidesAPIError: Error, LocalizedError, Equatable, Sendable {
    public var message: String
    public var statusCode: Int

    public init(message: String, statusCode: Int) {
        self.message = message
        self.statusCode = statusCode
    }

    public var errorDescription: String? { message }
}

/// Thin async/await URLSession client for tides-api. Used once per location
/// to download harmonic parameters; all predictions afterwards are computed
/// locally by `TidePredictor`.
public struct TidesAPIClient: TidesAPIClientProtocol {
    /// Default API host, used when the `API_HOST` Info.plist key is absent.
    public static let defaultHost = "api.tides.ngs.io"

    public var host: String
    public var session: URLSession

    public init(host: String, session: URLSession = .shared) {
        self.host = host
        self.session = session
    }

    /// Creates a client using the `API_HOST` Info.plist key.
    public init() {
        let host = Bundle.main.object(forInfoDictionaryKey: "API_HOST") as? String
        if let host, !host.isEmpty {
            self.init(host: host)
        } else {
            self.init(host: Self.defaultHost)
        }
    }

    public func fetchParameters(latitude: Double, longitude: Double) async throws -> HarmonicParameters {
        var components = URLComponents()
        components.scheme = "https"
        components.host = host
        components.path = "/v1/tides/parameters"
        components.queryItems = [
            URLQueryItem(name: "lat", value: String(latitude)),
            URLQueryItem(name: "lon", value: String(longitude))
        ]
        guard let url = components.url else {
            throw URLError(.badURL)
        }

        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }

        let decoder = HarmonicParameters.decoder()

        guard http.statusCode == 200 else {
            // 404 means the FES grid has no tidal data at the coordinate —
            // in practice, the point is on land. The server's message is
            // English-only, so replace it with a localized one.
            if http.statusCode == 404 {
                throw TidesAPIError(
                    message: String(localized: "No tide data is available for this location. It may be on land."),
                    statusCode: http.statusCode
                )
            }
            struct ErrorBody: Decodable { var error: String }
            if let body = try? decoder.decode(ErrorBody.self, from: data) {
                throw TidesAPIError(message: body.error, statusCode: http.statusCode)
            }
            throw TidesAPIError(
                message: String(localized: "The server returned an invalid response."),
                statusCode: http.statusCode
            )
        }

        do {
            return try decoder.decode(HarmonicParameters.self, from: data)
        } catch {
            // Callers show the error message as-is; a DecodingError reads far
            // too technical, so surface the same message a broken error body
            // gets above.
            throw TidesAPIError(
                message: String(localized: "The server returned an invalid response."),
                statusCode: http.statusCode
            )
        }
    }
}
