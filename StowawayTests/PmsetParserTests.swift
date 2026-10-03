import XCTest
@testable import Stowaway

final class PmsetParserTests: XCTestCase {
    func testMissingKeyMeansSleepAllowed() {
        let output = """
        System-wide power settings:
        Currently in use:
         standby              1
         Sleep On Power Button 1
         sleep                1 (sleep prevented by powerd, coreaudiod)
        """
        XCTAssertFalse(PmsetParser.sleepDisabled(in: output))
    }

    func testSleepDisabledOne() {
        let output = """
        System-wide power settings:
         SleepDisabled\t\t1
        Currently in use:
         sleep                1
        """
        XCTAssertTrue(PmsetParser.sleepDisabled(in: output))
    }

    func testSleepDisabledZero() {
        XCTAssertFalse(PmsetParser.sleepDisabled(in: "System-wide power settings:\n SleepDisabled\t\t0\n"))
    }

    func testEmptyOutput() {
        XCTAssertFalse(PmsetParser.sleepDisabled(in: ""))
    }
}
