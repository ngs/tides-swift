import Foundation

/// Harmonic constituent parameters for one location, as served by
/// `GET /v1/tides/parameters` on tides-api. Once downloaded, these are all
/// the data needed to predict tides offline for that location.
public struct HarmonicParameters: Codable, Equatable, Sendable {
    public struct Location: Codable, Equatable, Sendable {
        public var lat: Double
        public var lon: Double

        public init(lat: Double, lon: Double) {
            self.lat = lat
            self.lon = lon
        }
    }

    public struct Constituent: Codable, Equatable, Sendable {
        /// Constituent name, e.g. "M2", "S2", "K1".
        public var name: String
        /// Angular speed in degrees per hour.
        public var speedDegPerHour: Double
        /// Amplitude in meters.
        public var amplitudeMeters: Double
        /// Greenwich phase lag in degrees.
        public var phaseDegrees: Double
        /// Greenwich equilibrium argument V evaluated at `referenceTime`,
        /// in degrees. Precomputed by the server so clients only need the
        /// nodal corrections (f, u) locally.
        public var equilibriumArgumentDegrees: Double

        public init(
            name: String,
            speedDegPerHour: Double,
            amplitudeMeters: Double,
            phaseDegrees: Double,
            equilibriumArgumentDegrees: Double
        ) {
            self.name = name
            self.speedDegPerHour = speedDegPerHour
            self.amplitudeMeters = amplitudeMeters
            self.phaseDegrees = phaseDegrees
            self.equilibriumArgumentDegrees = equilibriumArgumentDegrees
        }

        enum CodingKeys: String, CodingKey {
            case name
            case speedDegPerHour = "speed_deg_per_hr"
            case amplitudeMeters = "amplitude_m"
            case phaseDegrees = "phase_deg"
            case equilibriumArgumentDegrees = "equilibrium_argument_deg"
        }
    }

    /// Location of the parameters (present for lat/lon queries).
    public var location: Location?
    /// Station identifier (present for station queries).
    public var stationID: String?
    /// Data source, "fes" or "csv".
    public var source: String
    /// Vertical datum name, e.g. "MSL".
    public var datum: String
    /// Constant term in meters added to the harmonic sum.
    public var mslMeters: Double
    /// Seabed depth in meters (positive down), if bathymetry is available.
    public var seabedDepthMeters: Double?
    /// Reference epoch the phase lags are expressed against.
    public var referenceTime: Date
    /// Harmonic constituents.
    public var constituents: [Constituent]

    public init(
        location: Location?,
        stationID: String?,
        source: String,
        datum: String,
        mslMeters: Double,
        seabedDepthMeters: Double?,
        referenceTime: Date,
        constituents: [Constituent]
    ) {
        self.location = location
        self.stationID = stationID
        self.source = source
        self.datum = datum
        self.mslMeters = mslMeters
        self.seabedDepthMeters = seabedDepthMeters
        self.referenceTime = referenceTime
        self.constituents = constituents
    }

    enum CodingKeys: String, CodingKey {
        case location
        case stationID = "station_id"
        case source
        case datum
        case mslMeters = "msl_m"
        case seabedDepthMeters = "seabed_depth_m"
        case referenceTime = "reference_time"
        case constituents
    }

    /// A `JSONDecoder` configured for the tides-api response format
    /// (`reference_time` is an RFC 3339 / ISO 8601 string).
    public static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
