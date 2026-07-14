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
    /// Constant term in meters added to the harmonic sum. Under the current
    /// API contract this is always 0 (heights are referenced to mean sea
    /// level); the field is kept so pre-redesign responses still decode.
    public var mslMeters: Double
    /// How far chart datum (Z0) lies *below* mean sea level, in meters
    /// (non-negative), as computed by the server: the JMA fit intercept at
    /// stations that have one, otherwise `Σ(H_M2 + H_S2 + H_K1 + H_O1)`.
    ///
    /// `nil` when the server did not supply it — a pre-redesign response, or a
    /// source that omits the field. Callers read `chartDatumOffsetMeters`,
    /// which falls back to the local amplitude sum when this is absent.
    public var serverChartDatumOffsetMeters: Double?
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
        serverChartDatumOffsetMeters: Double? = nil,
        seabedDepthMeters: Double?,
        referenceTime: Date,
        constituents: [Constituent]
    ) {
        self.location = location
        self.stationID = stationID
        self.source = source
        self.datum = datum
        self.mslMeters = mslMeters
        self.serverChartDatumOffsetMeters = serverChartDatumOffsetMeters
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
        case serverChartDatumOffsetMeters = "chart_datum_offset_m"
        case seabedDepthMeters = "seabed_depth_m"
        case referenceTime = "reference_time"
        case constituents
    }

    /// Constituents that define chart datum: the four principal semi-diurnal
    /// and diurnal tides.
    public static let chartDatumConstituents: Set<String> = ["M2", "S2", "K1", "O1"]

    /// How far chart datum (Z0) lies *below* mean sea level, in meters
    /// (non-negative).
    ///
    /// Prefers the server-computed `serverChartDatumOffsetMeters` when present
    /// (the JMA fit intercept, or the server's own amplitude sum), and falls
    /// back to `localChartDatumOffsetMeters` — the classic Japanese definition
    /// `Z0 = MSL − (H_M2 + H_S2 + H_K1 + H_O1)` — when the server did not
    /// supply a value.
    ///
    /// A height measured from Z0 is therefore the MSL-referenced height *plus*
    /// this offset.
    public var chartDatumOffsetMeters: Double {
        if let server = serverChartDatumOffsetMeters {
            // The contract guarantees a non-negative value; clamp defensively
            // so a bad value can never put Z0 above mean sea level.
            return max(0, server)
        }
        return localChartDatumOffsetMeters
    }

    /// Chart datum offset computed locally from the harmonic constituents:
    /// `Σ(H_M2 + H_S2 + H_K1 + H_O1)`, the Japanese convention (JMA / Japan
    /// Coast Guard). Constituents missing from the parameters simply contribute
    /// nothing to the sum. Used as the fallback when the server did not supply
    /// `serverChartDatumOffsetMeters`.
    public var localChartDatumOffsetMeters: Double {
        constituents
            .filter { Self.chartDatumConstituents.contains($0.name.uppercased()) }
            .reduce(0) { $0 + abs($1.amplitudeMeters) }
    }

    /// True for parameters saved under the pre-redesign API contract, where
    /// `msl_m` carried a datum intercept (the DL basis near JMA stations, or a
    /// mean-dynamic-topography term offshore) and `chart_datum_offset_m` did
    /// not exist yet.
    ///
    /// Current-contract responses always report `msl_m == 0` and include the
    /// offset field, so the two conditions together identify legacy data
    /// without a persisted schema flag.
    public var isLegacyDatumFormat: Bool {
        serverChartDatumOffsetMeters == nil && mslMeters != 0
    }

    /// Returns parameters normalized to the current datum contract.
    ///
    /// Non-legacy parameters are returned unchanged. For legacy data the stray
    /// `msl_m` intercept is reinterpreted as the chart datum offset and `msl_m`
    /// is reset to 0: near JMA stations that intercept is the published DL
    /// basis, which is exactly what the redesigned server now returns as
    /// `chart_datum_offset_m`, so this both removes the old double-counting
    /// (`msl_m` + local amplitude sum) and reproduces the new value closely.
    /// Offshore points get an approximate offset until their parameters are
    /// re-fetched (which happens when the location is moved or re-added).
    public func migratedToCurrentDatumContract() -> HarmonicParameters {
        guard isLegacyDatumFormat else { return self }
        var migrated = self
        migrated.serverChartDatumOffsetMeters = max(0, mslMeters)
        migrated.mslMeters = 0
        return migrated
    }

    /// A `JSONDecoder` configured for the tides-api response format
    /// (`reference_time` is an RFC 3339 / ISO 8601 string).
    public static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
