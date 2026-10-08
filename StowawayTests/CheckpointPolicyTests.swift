import XCTest
@testable import Stowaway

final class CheckpointPolicyTests: XCTestCase {
    private let closed = SystemSnapshot.healthy.with { $0.lidClosed = true }

    func testTimerAndBatteryGetAMinute() {
        XCTAssertEqual(CheckpointPolicy.grace(for: .timerFinished, system: closed), 60)
        XCTAssertEqual(CheckpointPolicy.grace(for: .lowBattery(20), system: closed), 60)
    }

    func testHeatGetsLess() {
        let hot = closed.with { $0.thermal = .serious }
        XCTAssertEqual(CheckpointPolicy.grace(for: .thermal, system: hot), 20)
        XCTAssertEqual(CheckpointPolicy.grace(for: .timerFinished, system: hot), 20)
    }

    func testCriticalHeatSleepsAtOnce() {
        let critical = closed.with { $0.thermal = .critical }
        XCTAssertEqual(CheckpointPolicy.grace(for: .thermal, system: critical), 0)
        XCTAssertEqual(CheckpointPolicy.grace(for: .lowBattery(15), system: critical), 0)
    }

    func testNoWaitWhenTheMacWontSleep() {
        XCTAssertEqual(CheckpointPolicy.grace(for: .timerFinished, system: .healthy), 0)
        XCTAssertEqual(CheckpointPolicy.grace(for: .timerFinished, system: closed.with { $0.externalDisplay = true }), 0)
    }

    func testStopsYouChoseNeverWait() {
        for reason in [EndReason.manual, .quit, .recovered] {
            XCTAssertEqual(CheckpointPolicy.grace(for: reason, system: closed), 0)
        }
    }
}
