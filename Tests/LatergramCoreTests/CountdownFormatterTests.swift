import XCTest
@testable import LatergramCore

final class CountdownFormatterTests: XCTestCase {
    func test_format_dHms() {
        let text = CountdownFormatter.dHms(from: 90061)
        XCTAssertEqual(text, "1天 01:01:01")
    }
}
