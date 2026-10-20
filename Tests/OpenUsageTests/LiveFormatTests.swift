import XCTest
@testable import OpenUsage

final class LiveFormatTests: XCTestCase {
    func testCompactKeepsThreeSignificantDigits() {
        XCTAssertEqual(LiveFormat.compact(950), "950")
        XCTAssertEqual(LiveFormat.compact(9_123), "9.12K")
        XCTAssertEqual(LiveFormat.compact(545_000), "545K")
        XCTAssertEqual(LiveFormat.compact(1_290_000), "1.29M")
        XCTAssertEqual(LiveFormat.compact(1_500_000), "1.50M")
        XCTAssertEqual(LiveFormat.compact(40_910_000), "40.9M")
        XCTAssertEqual(LiveFormat.compact(409_000_000), "409M")
        XCTAssertEqual(LiveFormat.compact(7_600_000_000), "7.60B")
    }

    func testRoundingCarriesIntoTheNextSuffix() {
        XCTAssertEqual(LiveFormat.compact(999_700), "1.00M")
        XCTAssertEqual(LiveFormat.compact(99_960), "100K")
    }
}

extension LiveFormatTests {
    func testJustUnderAThousandBecomesK() {
        XCTAssertEqual(LiveFormat.compact(999.6), "1.00K")
    }
}
