import XCTest
@testable import TidesCore

final class TidesAPIClientTests: XCTestCase {
  func testAPIClientInitialization() {
    let client = TidesAPIClient()
    XCTAssertNotNil(client)
  }

  func testAPIClientWithCustomTimeout() {
    let client = TidesAPIClient(timeoutInterval: 60)
    XCTAssertNotNil(client)
  }

  // Note: Health check endpoint is not available (returns 404)
  // Real API testing should be done with integration tests
}
