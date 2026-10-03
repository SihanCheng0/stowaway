import XCTest
@testable import Stowaway

final class SafetyPolicyTests: XCTestCase {
    private let now = Date(timeIntervalSinceReferenceDate: 1_000_000)
    private let settings = SafetySettings(batteryFloor: 20, thermalGuard: true)

    private func evaluate(endDate: Date? = nil, system: SystemSnapshot = .healthy, settings: SafetySettings? = nil) -> EndReason? {
        SafetyPolicy.evaluate(now: now, endDate: endDate, system: system, settings: settings ?? self.settings)
    }

    func testHealthySessionContinues() {
        XCTAssertNil(evaluate(endDate: now.addingTimeInterval(60)))
    }

    func testTimerFinished() {
        XCTAssertEqual(evaluate(endDate: now), .timerFinished)
        XCTAssertEqual(evaluate(endDate: now.addingTimeInterval(-1)), .timerFinished)
    }

    func testUnlimitedNeverTimesOut() {
        XCTAssertNil(evaluate(endDate: nil))
    }

    func testBatteryAtFloorOnBatteryStops() {
        let system = SystemSnapshot.healthy.with { $0.battery.percent = 20 }
        XCTAssertEqual(evaluate(system: system), .lowBattery(20))
    }

    func testBatteryAboveFloorContinues() {
        let system = SystemSnapshot.healthy.with { $0.battery.percent = 21 }
        XCTAssertNil(evaluate(system: system))
    }

    func testLowBatteryWhilePluggedInContinues() {
        let system = SystemSnapshot.healthy.with {
            $0.battery = BatteryInfo(percent: 5, onBattery: false, charging: true)
        }
        XCTAssertNil(evaluate(system: system))
    }

    func testMacWithoutBatteryContinues() {
        XCTAssertNil(evaluate(system: SystemSnapshot.healthy.with { $0.battery = .none }))
    }

    func testThermalGuardStopsWhenHot() {
        for state in [ProcessInfo.ThermalState.serious, .critical] {
            XCTAssertEqual(evaluate(system: SystemSnapshot.healthy.with { $0.thermal = state }), .thermal)
        }
    }

    func testWarmIsFine() {
        XCTAssertNil(evaluate(system: SystemSnapshot.healthy.with { $0.thermal = .fair }))
    }

    func testThermalGuardOff() {
        let hot = SystemSnapshot.healthy.with { $0.thermal = .critical }
        XCTAssertNil(evaluate(system: hot, settings: SafetySettings(batteryFloor: 20, thermalGuard: false)))
    }

    func testOnlySafeguardsCountAsAutomatic() {
        XCTAssertTrue(EndReason.timerFinished.isAutomatic)
        XCTAssertTrue(EndReason.lowBattery(10).isAutomatic)
        XCTAssertTrue(EndReason.thermal.isAutomatic)
        XCTAssertFalse(EndReason.manual.isAutomatic)
        XCTAssertFalse(EndReason.quit.isAutomatic)
        XCTAssertFalse(EndReason.recovered.isAutomatic)
    }
}
