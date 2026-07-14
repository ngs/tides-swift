import Foundation
import Testing
import TidesCore

/// Decoding tests for the tides-api parameters response format.
struct HarmonicParametersDecodingTests {
    private static let sampleResponse = """
    {
      "location": { "lat": 35.376, "lon": 139.917 },
      "source": "fes",
      "datum": "MSL",
      "msl_m": 1.149969,
      "seabed_depth_m": 12.4,
      "reference_time": "2012-01-01T00:00:00Z",
      "constituents": [
        {
          "name": "M2",
          "speed_deg_per_hr": 28.9841042,
          "amplitude_m": 0.508,
          "phase_deg": 133.1,
          "equilibrium_argument_deg": 192.38409088108892
        },
        {
          "name": "K1",
          "speed_deg_per_hr": 15.0410686,
          "amplitude_m": 0.256,
          "phase_deg": 190.4,
          "equilibrium_argument_deg": 18.183900319242984
        }
      ]
    }
    """

    @Test
    func decodesAPIResponse() throws {
        let data = try #require(Self.sampleResponse.data(using: .utf8))
        let params = try HarmonicParameters.decoder()
            .decode(HarmonicParameters.self, from: data)

        #expect(params.location?.lat == 35.376)
        #expect(params.location?.lon == 139.917)
        #expect(params.stationID == nil)
        #expect(params.source == "fes")
        #expect(params.datum == "MSL")
        #expect(params.mslMeters == 1.149969)
        #expect(params.seabedDepthMeters == 12.4)
        #expect(params.referenceTime == Date(timeIntervalSince1970: 1_325_376_000))

        try #require(params.constituents.count == 2)
        let m2 = params.constituents[0]
        #expect(m2.name == "M2")
        #expect(m2.speedDegPerHour == 28.9841042)
        #expect(m2.amplitudeMeters == 0.508)
        #expect(m2.phaseDegrees == 133.1)
        #expect(m2.equilibriumArgumentDegrees == 192.38409088108892)
        #expect(params.constituents[1].name == "K1")
    }

    @Test
    func decodesServerChartDatumOffset() throws {
        let json = """
        {
          "location": { "lat": 35.376, "lon": 139.917 },
          "source": "fes",
          "datum": "MSL",
          "msl_m": 0.0,
          "chart_datum_offset_m": 0.83,
          "reference_time": "2012-01-01T00:00:00Z",
          "constituents": [
            {
              "name": "M2",
              "speed_deg_per_hr": 28.9841042,
              "amplitude_m": 0.508,
              "phase_deg": 133.1,
              "equilibrium_argument_deg": 192.38409088108892
            }
          ]
        }
        """
        let data = try #require(json.data(using: .utf8))
        let params = try HarmonicParameters.decoder()
            .decode(HarmonicParameters.self, from: data)

        #expect(params.mslMeters == 0.0)
        #expect(params.serverChartDatumOffsetMeters == 0.83)
        // The server value wins over the local amplitude sum (0.508).
        #expect(params.chartDatumOffsetMeters == 0.83)
        #expect(abs(params.localChartDatumOffsetMeters - 0.508) < 1e-12)
        #expect(params.isLegacyDatumFormat == false)
    }

    @Test
    func fallsBackToLocalOffsetWhenServerValueAbsent() throws {
        let data = try #require(Self.sampleResponse.data(using: .utf8))
        let params = try HarmonicParameters.decoder()
            .decode(HarmonicParameters.self, from: data)

        // The sample response predates `chart_datum_offset_m`.
        #expect(params.serverChartDatumOffsetMeters == nil)
        // Only M2 (0.508) and K1 (0.256) of the four principal constituents
        // are present, so the local fallback is their amplitude sum.
        #expect(abs(params.chartDatumOffsetMeters - (0.508 + 0.256)) < 1e-12)
        #expect(abs(params.localChartDatumOffsetMeters - (0.508 + 0.256)) < 1e-12)
    }

    @Test
    func omitsServerOffsetKeyWhenNil() throws {
        let params = HarmonicParameters(
            location: nil,
            stationID: "JP-0123",
            source: "csv",
            datum: "MSL",
            mslMeters: 0,
            seabedDepthMeters: nil,
            referenceTime: Date(timeIntervalSince1970: 0),
            constituents: []
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let text = try #require(String(data: encoder.encode(params), encoding: .utf8))
        #expect(!text.contains("chart_datum_offset_m"))

        // And a value round-trips through the encoder when present.
        var withOffset = params
        withOffset.serverChartDatumOffsetMeters = 0.72
        let roundTripped = try HarmonicParameters.decoder()
            .decode(HarmonicParameters.self, from: encoder.encode(withOffset))
        #expect(roundTripped.serverChartDatumOffsetMeters == 0.72)
    }

    @Test
    func decodesStationResponseWithoutOptionalFields() throws {
        let json = """
        {
          "station_id": "JP-0123",
          "source": "csv",
          "datum": "MSL",
          "msl_m": 0.0,
          "reference_time": "1970-01-01T00:00:00Z",
          "constituents": []
        }
        """
        let data = try #require(json.data(using: .utf8))
        let params = try HarmonicParameters.decoder()
            .decode(HarmonicParameters.self, from: data)

        #expect(params.stationID == "JP-0123")
        #expect(params.location == nil)
        #expect(params.seabedDepthMeters == nil)
        #expect(params.referenceTime == Date(timeIntervalSince1970: 0))
        #expect(params.constituents.isEmpty)
    }
}
