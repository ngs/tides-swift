import XCTest
@testable import TidesCore

final class TidesAPIClientTests: XCTestCase {
  func testAPIClientInitialization() {
    let client = TidesAPIClient()
    XCTAssertNotNil(client)
  }

  func testHealthCheck() async {
    let client = TidesAPIClient()
    let isHealthy = await client.checkHealth()
    // API should be healthy
    XCTAssertTrue(isHealthy)
  }
}
