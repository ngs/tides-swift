import XCTest
@testable import TidesCore

final class TideModelsTests: XCTestCase {
  func testDecodeTidePredictionsResponse_Ocean() throws {
    let json = """
    {
      "source": "fes",
      "datum": "MSL",
      "timezone": "+09:00",
      "constituents": ["M2", "S2", "N2"],
      "predictions": [
        {
          "time": "2025-10-28T09:00:00+09:00",
          "height_m": 3.024
        },
        {
          "time": "2025-10-28T09:30:00+09:00",
          "height_m": 3.039
        }
      ],
      "extrema": {
        "highs": [
          {
            "time": "2025-10-28T09:42:46+09:00",
            "height_m": 3.04
          }
        ],
        "lows": [
          {
            "time": "2025-10-28T13:56:58+09:00",
            "height_m": 2.883
          }
        ]
      },
      "msl_m": 0.3309021362306339
    }
    """

    let data = json.data(using: .utf8)!
    let decoder = JSONDecoder()
    let response = try decoder.decode(TidePredictionsResponse.self, from: data)

    // Verify basic fields
    XCTAssertEqual(response.source, "fes")
    XCTAssertEqual(response.datum, "MSL")
    XCTAssertEqual(response.timezone, "+09:00")
    XCTAssertEqual(response.constituents?.count, 3)
    XCTAssertEqual(response.mslM, 0.3309021362306339)

    // Verify predictions
    XCTAssertEqual(response.predictions.count, 2)
    XCTAssertEqual(response.predictions[0].time, "2025-10-28T09:00:00+09:00")
    XCTAssertEqual(response.predictions[0].heightM, 3.024, accuracy: 0.001)
    XCTAssertNil(response.predictions[0].depthM)

    // Verify extrema
    XCTAssertNotNil(response.extrema)
    XCTAssertEqual(response.extrema?.highs.count, 1)
    if let firstHigh = response.extrema?.highs.first {
      XCTAssertEqual(firstHigh.heightM, 3.04, accuracy: 0.001)
    } else {
      XCTFail("Expected at least one high tide")
    }
    XCTAssertEqual(response.extrema?.lows.count, 1)
    if let firstLow = response.extrema?.lows.first {
      XCTAssertEqual(firstLow.heightM, 2.883, accuracy: 0.001)
    } else {
      XCTFail("Expected at least one low tide")
    }
  }

  func testDecodeTidePredictionsResponse_Land() throws {
    let json = """
    {
      "source": "fes",
      "predictions": [
        {
          "time": "2025-10-28T09:00:00+09:00",
          "height_m": 3.024,
          "depth_m": null
        }
      ],
      "extrema": {
        "highs": [],
        "lows": []
      }
    }
    """

    let data = json.data(using: .utf8)!
    let decoder = JSONDecoder()
    let response = try decoder.decode(TidePredictionsResponse.self, from: data)

    XCTAssertEqual(response.source, "fes")
    XCTAssertEqual(response.predictions.count, 1)
    XCTAssertNil(response.predictions[0].depthM, "depth_m should be nil for land")
  }

  func testDecodeTidePredictionsResponse_Minimal() throws {
    let json = """
    {
      "source": "fes",
      "predictions": [
        {
          "time": "2025-10-28T09:00:00Z",
          "height_m": 3.024
        }
      ]
    }
    """

    let data = json.data(using: .utf8)!
    let decoder = JSONDecoder()
    let response = try decoder.decode(TidePredictionsResponse.self, from: data)

    XCTAssertEqual(response.source, "fes")
    XCTAssertEqual(response.predictions.count, 1)
    XCTAssertNil(response.extrema, "extrema should be optional")
    XCTAssertNil(response.datum)
    XCTAssertNil(response.timezone)
    XCTAssertNil(response.constituents)
    XCTAssertNil(response.mslM)
  }

  func testDecodeTidePredictionsResponse_NoExtrema() throws {
    let json = """
    {
      "source": "fes",
      "predictions": [
        {
          "time": "2025-10-28T09:00:00Z",
          "height_m": 3.024
        }
      ],
      "extrema": null
    }
    """

    let data = json.data(using: .utf8)!
    let decoder = JSONDecoder()
    let response = try decoder.decode(TidePredictionsResponse.self, from: data)

    XCTAssertEqual(response.source, "fes")
    XCTAssertNil(response.extrema)
  }

  func testTidePrediction_DateConversion() throws {
    let prediction = TidePrediction(
      time: "2025-10-28T09:00:00Z",
      heightM: 3.024,
      depthM: nil
    )

    XCTAssertNotNil(prediction.date, "Should be able to parse ISO8601 date")

    let invalidPrediction = TidePrediction(
      time: "invalid-date",
      heightM: 3.024,
      depthM: nil
    )

    XCTAssertNil(invalidPrediction.date, "Should return nil for invalid date")
  }

  func testTideExtreme_DateConversion() throws {
    let extreme = TideExtreme(
      time: "2025-10-28T09:42:46+09:00",
      heightM: 3.04
    )

    XCTAssertNotNil(extreme.date, "Should be able to parse ISO8601 date with timezone")
  }

  func testMapPosition_Default() {
    let defaultPosition = MapPosition.default

    XCTAssertEqual(defaultPosition.lat, 35.6, accuracy: 0.1)
    XCTAssertEqual(defaultPosition.lon, 139.8, accuracy: 0.1)
    XCTAssertEqual(defaultPosition.zoom, 10, accuracy: 0.1)
  }

  func testMapPosition_Equatable() {
    let pos1 = MapPosition(lat: 35.6, lon: 139.8, zoom: 10)
    let pos2 = MapPosition(lat: 35.6, lon: 139.8, zoom: 10)
    let pos3 = MapPosition(lat: 35.7, lon: 139.8, zoom: 10)

    XCTAssertEqual(pos1, pos2)
    XCTAssertNotEqual(pos1, pos3)
  }
}
