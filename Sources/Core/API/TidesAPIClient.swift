import Foundation
import Logging

/// Error types for Tides API
public enum TidesAPIError: Error, LocalizedError, Sendable {
  case invalidURL
  case networkError(Error)
  case invalidResponse
  case httpError(statusCode: Int, message: String)
  case decodingError(Error)

  public var errorDescription: String? {
    switch self {
    case .invalidURL:
      "Invalid API URL"
    case .networkError(let error):
      "Network error: \(error.localizedDescription)"
    case .invalidResponse:
      "Invalid response from API"
    case .httpError(let statusCode, let message):
      "HTTP error \(statusCode): \(message)"
    case .decodingError(let error):
      "Failed to decode response: \(error.localizedDescription)"
    }
  }
}

/// Client for the Tides API
public actor TidesAPIClient {
  private let baseURL: String
  private let session: URLSession
  private let logger = Logger(label: "io.ngs.Tides.TidesAPIClient")

  public init(
    baseURL: String = "https://api.tides.ngs.io",
    session: URLSession = .shared
  ) {
    self.baseURL = baseURL
    self.session = session
  }

  /// Fetch tide predictions for a specific location and time range
  public func fetchTidePredictions(
    lat: Double,
    lon: Double,
    start: Date,
    end: Date,
    interval: String = "30m",
    source: String = "fes"
  ) async throws -> TidePredictionsResponse {
    var components = URLComponents(string: "\(baseURL)/v1/tides/predictions")
    guard components != nil else {
      throw TidesAPIError.invalidURL
    }

    let formatter = ISO8601DateFormatter()
    components?.queryItems = [
      URLQueryItem(name: "lat", value: String(lat)),
      URLQueryItem(name: "lon", value: String(lon)),
      URLQueryItem(name: "start", value: formatter.string(from: start)),
      URLQueryItem(name: "end", value: formatter.string(from: end)),
      URLQueryItem(name: "interval", value: interval),
      URLQueryItem(name: "source", value: source),
    ]

    guard let url = components?.url else {
      throw TidesAPIError.invalidURL
    }

    logger.debug("Fetching tide predictions from \(url.absoluteString)")

    do {
      let (data, response) = try await session.data(from: url)

      guard let httpResponse = response as? HTTPURLResponse else {
        throw TidesAPIError.invalidResponse
      }

      guard httpResponse.statusCode == 200 else {
        let message = String(data: data, encoding: .utf8) ?? "Unknown error"
        throw TidesAPIError.httpError(statusCode: httpResponse.statusCode, message: message)
      }

      do {
        let decoder = JSONDecoder()
        let result = try decoder.decode(TidePredictionsResponse.self, from: data)
        logger.debug("Successfully fetched \(result.predictions.count) predictions")
        return result
      } catch {
        logger.error("Failed to decode response: \(error)")
        throw TidesAPIError.decodingError(error)
      }
    } catch let error as TidesAPIError {
      throw error
    } catch {
      logger.error("Network error: \(error)")
      throw TidesAPIError.networkError(error)
    }
  }

  /// Fetch available tidal constituents
  public func fetchConstituents() async throws -> [Constituent] {
    guard let url = URL(string: "\(baseURL)/v1/constituents") else {
      throw TidesAPIError.invalidURL
    }

    logger.debug("Fetching constituents from \(url.absoluteString)")

    do {
      let (data, response) = try await session.data(from: url)

      guard let httpResponse = response as? HTTPURLResponse else {
        throw TidesAPIError.invalidResponse
      }

      guard httpResponse.statusCode == 200 else {
        let message = String(data: data, encoding: .utf8) ?? "Unknown error"
        throw TidesAPIError.httpError(statusCode: httpResponse.statusCode, message: message)
      }

      do {
        let decoder = JSONDecoder()
        let result = try decoder.decode([Constituent].self, from: data)
        logger.debug("Successfully fetched \(result.count) constituents")
        return result
      } catch {
        logger.error("Failed to decode response: \(error)")
        throw TidesAPIError.decodingError(error)
      }
    } catch let error as TidesAPIError {
      throw error
    } catch {
      logger.error("Network error: \(error)")
      throw TidesAPIError.networkError(error)
    }
  }

  /// Check API health status
  public func checkHealth() async -> Bool {
    guard let url = URL(string: "\(baseURL)/healthz") else {
      return false
    }

    do {
      let (_, response) = try await session.data(from: url)
      guard let httpResponse = response as? HTTPURLResponse else {
        return false
      }
      return httpResponse.statusCode == 200
    } catch {
      logger.error("Health check failed: \(error)")
      return false
    }
  }
}
