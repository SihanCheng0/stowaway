import XCTest
@testable import Stowaway

@MainActor
final class AwakeControllerTests: XCTestCase {
    private var power = MockPower()
    private var monitor = MockMonitor()
    private var authorizer = MockAuthorizer()
    private var defaults = makeTestDefaults()

    private func makeController() -> AwakeController {
        AwakeController(power: power, monitor: monitor, authorizer: authorizer, defaults: defaults)
    }

    private func activeController(_ duration: AwakeDuration = .twoHours) -> AwakeController {
        let controller = makeController()
        controller.syncOnLaunch()
        controller.select(duration)
        controller.enable()
        return controller
    }

    // MARK: - Enabling

    func testEnableDisablesSleepAndStartsCountdown() throws {
        let controller = activeController(.oneHour)
        XCTAssertTrue(controller.isActive)
        XCTAssertTrue(power.sleepDisabled)
        let remaining = try XCTUnwrap(controller.remaining)
        XCTAssertEqual(remaining, 3600, accuracy: 1)
        XCTAssertTrue(defaults.bool(forKey: "sessionActive"))
    }

    func testUnlimitedHasNoEndDate() {
        let controller = activeController(.unlimited)
        XCTAssertTrue(controller.isActive)
        XCTAssertNil(controller.endDate)
    }

    func testEnableAuthorizesFirstWhenNeeded() {
        authorizer.installed = false
        let controller = activeController()
        XCTAssertEqual(authorizer.installCalls, 1)
        XCTAssertTrue(controller.isAuthorized)
        XCTAssertTrue(controller.isActive)
    }

    func testCancelledAuthorizationLeavesSleepAlone() {
        authorizer.installed = false
        authorizer.installError = StowawayError.cancelled
        let controller = activeController()
        XCTAssertFalse(controller.isActive)
        XCTAssertTrue(power.setCalls.isEmpty)
        XCTAssertNil(controller.notice)
    }

    func testRefusesToStartBelowBatteryFloor() {
        monitor.current = SystemSnapshot.healthy.with { $0.battery.percent = 12 }
        let controller = activeController()
        XCTAssertFalse(controller.isActive)
        XCTAssertTrue(power.setCalls.isEmpty)
        XCTAssertEqual(controller.notice, "Not started: battery at 12%.")
    }

    func testPmsetFailureIsReported() {
        power.shouldFail = true
        let controller = activeController()
        XCTAssertFalse(controller.isActive)
        XCTAssertEqual(controller.notice, "pmset refused")
    }

    // MARK: - Countdown

    func testExtendAddsThirtyMinutes() throws {
        let controller = activeController(.oneHour)
        let before = try XCTUnwrap(controller.endDate)
        controller.extend()
        XCTAssertEqual(try XCTUnwrap(controller.endDate).timeIntervalSince(before), 1800, accuracy: 0.5)
    }

    func testSelectingDurationRestartsCountdown() throws {
        let controller = activeController(.fourHours)
        controller.select(.thirtyMinutes)
        XCTAssertEqual(try XCTUnwrap(controller.remaining), 1800, accuracy: 1)
        XCTAssertEqual(controller.duration, .thirtyMinutes)
    }

    func testTimerExpiryRestoresSleep() throws {
        let controller = activeController(.thirtyMinutes)
        let end = try XCTUnwrap(controller.endDate)
        controller.tick(at: end.addingTimeInterval(-1))
        XCTAssertTrue(controller.isActive)
        controller.tick(at: end.addingTimeInterval(1))
        XCTAssertFalse(controller.isActive)
        XCTAssertFalse(power.sleepDisabled)
        XCTAssertEqual(controller.lastEnd?.reason, .timerFinished)
        XCTAssertFalse(defaults.bool(forKey: "sessionActive"))
    }

    // MARK: - Safeguards

    func testBatteryGuardEndsSession() {
        let controller = activeController()
        monitor.current = SystemSnapshot.healthy.with { $0.battery.percent = 19 }
        controller.refreshSystem()
        controller.tick()
        XCTAssertFalse(controller.isActive)
        XCTAssertEqual(controller.lastEnd?.reason, .lowBattery(19))
    }

    func testThermalGuardEndsSession() {
        let controller = activeController()
        monitor.current = SystemSnapshot.healthy.with { $0.thermal = .serious }
        controller.refreshSystem()
        controller.tick()
        XCTAssertEqual(controller.lastEnd?.reason, .thermal)
    }

    func testAutoStopWithLidClosedSleepsImmediately() throws {
        let controller = activeController(.thirtyMinutes)
        monitor.current = SystemSnapshot.healthy.with { $0.lidClosed = true }
        controller.refreshSystem()
        controller.tick(at: try XCTUnwrap(controller.endDate).addingTimeInterval(1))
        XCTAssertEqual(power.sleepNowCount, 1)
    }

    func testAutoStopWithExternalDisplayDoesNotForceSleep() throws {
        let controller = activeController(.thirtyMinutes)
        monitor.current = SystemSnapshot.healthy.with {
            $0.lidClosed = true
            $0.externalDisplay = true
        }
        controller.refreshSystem()
        controller.tick(at: try XCTUnwrap(controller.endDate).addingTimeInterval(1))
        XCTAssertFalse(controller.isActive)
        XCTAssertEqual(power.sleepNowCount, 0)
    }

    func testManualStopNeverForcesSleep() {
        let controller = activeController()
        monitor.current = SystemSnapshot.healthy.with { $0.lidClosed = true }
        controller.refreshSystem()
        controller.toggle()
        XCTAssertFalse(controller.isActive)
        XCTAssertEqual(power.sleepNowCount, 0)
    }

    func testFailedAutoStopIsRetriedLaterNotEveryTick() throws {
        let controller = activeController(.thirtyMinutes)
        let end = try XCTUnwrap(controller.endDate)
        power.shouldFail = true
        controller.tick(at: end.addingTimeInterval(1))
        controller.tick(at: end.addingTimeInterval(2))
        controller.tick(at: end.addingTimeInterval(3))
        XCTAssertEqual(power.setCalls, [true, false])
        XCTAssertTrue(controller.isActive)

        power.shouldFail = false
        controller.tick(at: end.addingTimeInterval(40))
        XCTAssertFalse(controller.isActive)
        XCTAssertEqual(power.setCalls, [true, false, false])
    }

    // MARK: - Launch and quit

    func testRecoversStaleSessionAfterCrash() {
        power.sleepDisabled = true
        defaults.set(true, forKey: "sessionActive")
        let controller = makeController()
        controller.syncOnLaunch()
        XCTAssertFalse(controller.isActive)
        XCTAssertFalse(power.sleepDisabled)
        XCTAssertEqual(controller.lastEnd?.reason, .recovered)
    }

    func testExternalStateIsShownButNotUndoneOnQuit() {
        power.sleepDisabled = true
        let controller = makeController()
        controller.syncOnLaunch()
        XCTAssertTrue(controller.isActive)
        XCTAssertTrue(controller.isExternal)
        controller.restoreForQuit()
        XCTAssertTrue(power.sleepDisabled)
    }

    func testQuitRestoresOwnSession() {
        let controller = activeController()
        controller.restoreForQuit()
        XCTAssertFalse(power.sleepDisabled)
        XCTAssertEqual(controller.lastEnd?.reason, .quit)
    }

    func testRemovingAuthorizationEndsSessionFirst() {
        let controller = activeController()
        controller.removeAuthorization()
        XCTAssertFalse(power.sleepDisabled)
        XCTAssertFalse(controller.isAuthorized)
    }

    func testSettingsPersist() {
        let controller = makeController()
        controller.batteryFloor = 35
        controller.thermalGuard = false
        controller.select(.fourHours)
        let reloaded = makeController()
        XCTAssertEqual(reloaded.batteryFloor, 35)
        XCTAssertFalse(reloaded.thermalGuard)
        XCTAssertEqual(reloaded.duration, .fourHours)
    }
}
