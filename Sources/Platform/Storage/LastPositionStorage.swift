import Foundation
import Logging
import TidesCore

/// Storage for the last viewed map position and location name
public actor LastPositionStorage {
  private let userDefaults: UserDefaults
  private let logger = Logger(label: "io.ngs.Tides.LastPositionStorage")

  private enum Keys {
    static let position = "lastMapPosition"
    static let locationName = "lastLocationName"
  }

  public init(userDefaults: UserDefaults = .standard) {
    self.userDefaults = userDefaults
  }

  /// Save the last viewed position and location name
  public func save(position: MapPosition, locationName: String) {
    do {
      let encoder = JSONEncoder()
      let data = try encoder.encode(position)
      userDefaults.set(data, forKey: Keys.position)
      userDefaults.set(locationName, forKey: Keys.locationName)
      logger.debug(
        "Saved position: lat=\(position.lat), lon=\(position.lon), location=\(locationName)")
    } catch {
      logger.error("Failed to save position: \(error)")
    }
  }

  /// Load the last viewed position and location name
  public func load() -> (position: MapPosition, locationName: String)? {
    guard let data = userDefaults.data(forKey: Keys.position),
      let locationName = userDefaults.string(forKey: Keys.locationName)
    else {
      logger.debug("No saved position found")
      return nil
    }

    do {
      let decoder = JSONDecoder()
      let position = try decoder.decode(MapPosition.self, from: data)
      logger.debug(
        "Loaded position: lat=\(position.lat), lon=\(position.lon), location=\(locationName)")
      return (position, locationName)
    } catch {
      logger.error("Failed to load position: \(error)")
      return nil
    }
  }

  /// Clear saved position
  public func clear() {
    userDefaults.removeObject(forKey: Keys.position)
    userDefaults.removeObject(forKey: Keys.locationName)
    logger.debug("Cleared saved position")
  }
}
