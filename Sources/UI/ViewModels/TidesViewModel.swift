import Combine
import Foundation
import Logging
import SwiftUI
import TidesCore
import TidesPlatform

/// View model for managing tide data and map state
@MainActor
public class TidesViewModel: ObservableObject {
  @Published public var mapPosition: MapPosition
  @Published public var predictions: [TidePrediction] = []
  @Published public var highs: [TideExtreme] = []
  @Published public var lows: [TideExtreme] = []
  @Published public var loading = false
  @Published public var error: String?
  @Published public var locationName = "Loading..."
  @Published public var selectedDate = Date()

  private let apiClient = TidesAPIClient()
  private let storage = LastPositionStorage()
  private let geocoding = GeocodingService()
  private let logger = Logger(label: "io.ngs.Tides.TidesViewModel")

  private var debouncedPositionTask: Task<Void, Never>?
  private var fetchTask: Task<Void, Never>?
  private var isInitialLoad = true

  public init() {
    // Initialize with default position
    self.mapPosition = .default

    // Load saved position and fetch data asynchronously
    Task {
      if let saved = await storage.load() {
        self.mapPosition = saved.position
        self.locationName = saved.locationName
        await fetchTideData(for: saved.position, date: selectedDate)
      } else {
        await fetchLocationName(for: mapPosition)
        await fetchTideData(for: mapPosition, date: selectedDate)
      }
      // Mark initial load complete
      self.isInitialLoad = false
    }
  }

  /// Handle map position change with debouncing
  public func handlePositionChange(_ newPosition: MapPosition) {
    // Skip if initial load is still in progress to avoid duplicate requests
    guard !isInitialLoad else {
      logger.debug("Skipping position change during initial load")
      return
    }

    // Skip if position hasn't actually changed significantly (avoid unnecessary API calls)
    let latDiff = abs(newPosition.lat - mapPosition.lat)
    let lonDiff = abs(newPosition.lon - mapPosition.lon)
    guard latDiff > 0.0001 || lonDiff > 0.0001 else {
      return
    }

    mapPosition = newPosition

    // Cancel previous debounce task
    debouncedPositionTask?.cancel()

    // Set loading state immediately
    locationName = "Loading..."

    // Debounce position changes
    debouncedPositionTask = Task {
      try? await Task.sleep(for: .milliseconds(500))

      guard !Task.isCancelled else { return }

      await fetchLocationName(for: newPosition)
      await fetchTideData(for: newPosition, date: selectedDate)
    }
  }

  /// Fetch location name using reverse geocoding
  private func fetchLocationName(for position: MapPosition) async {
    do {
      let name = try await geocoding.getLocationName(
        latitude: position.lat,
        longitude: position.lon
      )

      guard !Task.isCancelled else { return }

      locationName = name

      // Save position and location name
      await storage.save(position: position, locationName: name)
    } catch {
      logger.error("Failed to fetch location name: \(error)")
      locationName = "Unknown Location"
    }
  }

  /// Fetch tide predictions
  private func fetchTideData(for position: MapPosition, date: Date) async {
    // Cancel previous fetch task
    fetchTask?.cancel()

    fetchTask = Task {
      loading = true
      error = nil

      do {
        // Calculate start and end times (full day in UTC)
        var calendar = Calendar.current
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let start = calendar.startOfDay(for: date)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else {
          throw TidesAPIError.invalidURL
        }

        logger.debug("Fetching tide data for \(position.lat), \(position.lon) from \(start) to \(end)")

        let response = try await apiClient.fetchTidePredictions(
          lat: position.lat,
          lon: position.lon,
          start: start,
          end: end,
          interval: "30m",
          source: "fes"
        )

        guard !Task.isCancelled else { return }

        predictions = response.predictions
        highs = response.extrema?.highs ?? []
        lows = response.extrema?.lows ?? []

        logger.debug(
          "Fetched \(predictions.count) predictions, \(highs.count) highs, \(lows.count) lows")
      } catch {
        guard !Task.isCancelled else { return }

        logger.error("Failed to fetch tide data: \(error)")

        // Provide user-friendly error messages
        if let apiError = error as? TidesAPIError {
          switch apiError {
          case .httpError(let statusCode, _) where statusCode == 503:
            self.error = "Tide service is temporarily unavailable. Please try again later."
          case .httpError(let statusCode, let message):
            self.error = "API Error (\(statusCode)): \(message)"
          case .timeout:
            self.error = "Request timed out. Please check your internet connection and try again."
          case .networkError:
            self.error = "Network error. Please check your internet connection."
          default:
            self.error = error.localizedDescription
          }
        } else {
          self.error = error.localizedDescription
        }

        predictions = []
        highs = []
        lows = []
      }

      guard !Task.isCancelled else { return }
      loading = false
    }

    await fetchTask?.value
  }
}
