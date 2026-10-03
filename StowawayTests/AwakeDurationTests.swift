import XCTest
@testable import Stowaway

final class AwakeDurationTests: XCTestCase {
    func testIntervals() {
        XCTAssertEqual(AwakeDuration.thirtyMinutes.interval, 1800)
        XCTAssertEqual(AwakeDuration.fourHours.interval, 14400)
        XCTAssertNil(AwakeDuration.unlimited.interval)
    }

    func testLabels() {
        XCTAssertEqual(AwakeDuration.allCases.map(\.label), ["30m", "1h", "2h", "4h", "∞"])
    }

    func testClock() {
        XCTAssertEqual(Countdown.clock(7200), "2:00:00")
        XCTAssertEqual(Countdown.clock(7199.4), "2:00:00")
        XCTAssertEqual(Countdown.clock(6127), "1:42:07")
        XCTAssertEqual(Countdown.clock(59.2), "1:00")
        XCTAssertEqual(Countdown.clock(0), "0:00")
        XCTAssertEqual(Countdown.clock(-5), "0:00")
    }

    func testCompact() {
        XCTAssertEqual(Countdown.compact(7200), "2:00")
        XCTAssertEqual(Countdown.compact(6127), "1:42")
        XCTAssertEqual(Countdown.compact(30), "0:01")
        XCTAssertEqual(Countdown.compact(0), "0:00")
    }
}
