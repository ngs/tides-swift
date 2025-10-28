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

  public init() {
    // Try to load last position
    if let saved = Task { await storage.load() }.result {
      if case .success(let data) = saved, let data {
        self.mapPosition = data.position
        self.locationName = data.locationName
      } else {
        self.mapPosition = .default
      }
    } else {
      self.mapPosition = .default
    }

    // Start fetching initial data
    Task {
      await fetchLocationName(for: mapPosition)
      await fetchTideData(for: mapPosition, date: selectedDate)
    }
  }

  /// Handle map position change with debouncing
  public func handlePositionChange(_ newPosition: MapPosition) {
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
        // Calculate start and end times (full day)
        var calendar = Calendar.current
        calendar.timeZone = TimeZone.current
        let start = calendar.startOfDay(for: date)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else {
          throw TidesAPIError.invalidURL
        }

        logger.debug("Fetching tide data for \(position.lat), \(position.lon)")

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
        self.error = error.localizedDescription
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

extension Task where Success == Never, Failure == Never {
  var result: Result<Success, Error>? {
    get async {
      do {
        try await self.value
        return nil
      } catch {
        return .failure(error)
      }
    }
  }
}
