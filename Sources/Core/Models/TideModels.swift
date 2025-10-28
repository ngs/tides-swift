import Foundation

/// Tide prediction data point from the API
public struct TidePrediction: Codable, Identifiable, Sendable {
  /// ISO 8601 datetime string
  public let time: String
  /// Height in meters
  public let heightM: Double
  /// Water depth in meters (optional, not present for land)
  public let depthM: Double?

  public var id: String { time }

  /// Computed Date from time string
  public var date: Date? {
    ISO8601DateFormatter().date(from: time)
  }

  enum CodingKeys: String, CodingKey {
    case time
    case heightM = "height_m"
    case depthM = "depth_m"
  }

  public init(time: String, heightM: Double, depthM: Double? = nil) {
    self.time = time
    self.heightM = heightM
    self.depthM = depthM
  }
}

/// Tide extreme (high or low tide)
public struct TideExtreme: Codable, Identifiable, Sendable {
  /// ISO 8601 datetime string
  public let time: String
  /// Tide height in meters (relative to datum)
  public let heightM: Double

  public var id: String { time }

  /// Computed Date from time string
  public var date: Date? {
    ISO8601DateFormatter().date(from: time)
  }

  enum CodingKeys: String, CodingKey {
    case time
    case heightM = "height_m"
  }

  public init(time: String, heightM: Double) {
    self.time = time
    self.heightM = heightM
  }
}

/// Extrema (highs and lows)
public struct TideExtrema: Codable, Sendable {
  public let highs: [TideExtreme]
  public let lows: [TideExtreme]

  public init(highs: [TideExtreme], lows: [TideExtreme]) {
    self.highs = highs
    self.lows = lows
  }
}

/// Location information
public struct TideLocation: Codable, Sendable {
  public let lat: Double
  public let lon: Double

  public init(lat: Double, lon: Double) {
    self.lat = lat
    self.lon = lon
  }
}

/// API response for tide predictions
public struct TidePredictionsResponse: Codable, Sendable {
  public let predictions: [TidePrediction]
  public let extrema: TideExtrema?
  public let source: String
  public let datum: String?
  public let timezone: String?
  public let constituents: [String]?
  public let mslM: Double?

  enum CodingKeys: String, CodingKey {
    case predictions
    case extrema
    case source
    case datum
    case timezone
    case constituents
    case mslM = "msl_m"
  }

  public init(
    predictions: [TidePrediction],
    extrema: TideExtrema?,
    source: String,
    datum: String? = nil,
    timezone: String? = nil,
    constituents: [String]? = nil,
    mslM: Double? = nil
  ) {
    self.predictions = predictions
    self.extrema = extrema
    self.source = source
    self.datum = datum
    self.timezone = timezone
    self.constituents = constituents
    self.mslM = mslM
  }
}

/// Constituent data from the API
public struct Constituent: Codable, Identifiable, Sendable {
  public let name: String
  public let description: String
  public let speed: Double

  public var id: String { name }

  public init(name: String, description: String, speed: Double) {
    self.name = name
    self.description = description
    self.speed = speed
  }
}

/// Map position state
public struct MapPosition: Codable, Sendable, Equatable {
  public let lat: Double
  public let lon: Double
  public let zoom: Double

  public init(lat: Double, lon: Double, zoom: Double) {
    self.lat = lat
    self.lon = lon
    self.zoom = zoom
  }

  /// Default position (Tokyo Bay area)
  public static let `default` = MapPosition(lat: 35.6, lon: 139.8, zoom: 10)
}
