import Foundation
import Logging
import MapKit

/// Service for reverse geocoding using MapKit
public actor GeocodingService {
  private let geocoder = CLGeocoder()
  private let logger = Logger(label: "io.ngs.Tides.GeocodingService")
  private var cache: [String: String] = [:]

  public init() {}

  /// Get location name from coordinates using reverse geocoding
  public func getLocationName(latitude: Double, longitude: Double) async throws -> String {
    let cacheKey = "\(String(format: "%.4f", latitude)),\(String(format: "%.4f", longitude))"

    // Check cache first
    if let cached = cache[cacheKey] {
      logger.debug("Cache hit for \(cacheKey): \(cached)")
      return cached
    }

    let location = CLLocation(latitude: latitude, longitude: longitude)

    do {
      let placemarks = try await geocoder.reverseGeocodeLocation(location)

      guard let placemark = placemarks.first else {
        logger.warning("No placemark found for coordinates")
        return "Unknown Location"
      }

      // Format location name similar to web version
      var components: [String] = []

      // Add sublocality if available
      if let subLocality = placemark.subLocality {
        components.append(subLocality)
      }

      // Add locality (city) if available
      if let locality = placemark.locality {
        components.append(locality)
      }

      // If we don't have sublocality or locality, try administrative area
      if components.isEmpty, let administrativeArea = placemark.administrativeArea {
        components.append(administrativeArea)
      }

      // If still nothing, try country
      if components.isEmpty, let country = placemark.country {
        components.append(country)
      }

      let locationName =
        components.isEmpty ? "Unknown Location" : components.joined(separator: ", ")

      // Cache the result
      cache[cacheKey] = locationName
      logger.debug("Geocoded \(cacheKey) to \(locationName)")

      return locationName
    } catch {
      logger.error("Geocoding failed: \(error)")
      throw error
    }
  }

  /// Clear the geocoding cache
  public func clearCache() {
    cache.removeAll()
    logger.debug("Cleared geocoding cache")
  }
}
