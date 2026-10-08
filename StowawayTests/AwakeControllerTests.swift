import XCTest
@testable import Stowaway

@MainActor
final class AwakeControllerTests: XCTestCase {
    private var power = MockPower()
    private var monitor = MockMonitor()
    private var authorizer = MockAuthorizer()
    private var checkpoint = MockCheckpoint()
    private var defaults = makeTestDefaults()

    private func makeController() -> AwakeController {
        AwakeController(power: power, monitor: monitor, authorizer: authorizer, checkpoint: checkpoint, defaults: defaults)
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
        // The lid is open, so the Mac won't sleep and there's nothing to wait for.
        XCTAssertTrue(checkpoint.begun.isEmpty)
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

    func testAutoStopWithLidClosedSleepsImmediatelyWithoutCheckpoint() throws {
        let controller = activeController(.thirtyMinutes)
        controller.checkpointBeforeSleep = false
        monitor.current = SystemSnapshot.healthy.with { $0.lidClosed = true }
        controller.refreshSystem()
        controller.tick(at: try XCTUnwrap(controller.endDate).addingTimeInterval(1))
        XCTAssertEqual(power.sleepNowCount, 1)
        XCTAssertTrue(checkpoint.begun.isEmpty)
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
        XCTAssertTrue(controller.checkpointBeforeSleep)
        controller.batteryFloor = 35
        controller.thermalGuard = false
        controller.checkpointBeforeSleep = false
        controller.select(.fourHours)
        let reloaded = makeController()
        XCTAssertEqual(reloaded.batteryFloor, 35)
        XCTAssertFalse(reloaded.thermalGuard)
        XCTAssertFalse(reloaded.checkpointBeforeSleep)
        XCTAssertEqual(reloaded.duration, .fourHours)
    }

    // MARK: - Checkpoint before sleep

    private func closedLidController(_ duration: AwakeDuration = .thirtyMinutes) -> AwakeController {
        monitor.current = SystemSnapshot.healthy.with { $0.lidClosed = true }
        return activeController(duration)
    }

    /// Trips the timer with the lid closed and returns the checkpoint window it opened.
    private func startCheckpoint(_ controller: AwakeController) throws -> PendingSleep {
        controller.tick(at: try XCTUnwrap(controller.endDate).addingTimeInterval(1))
        return try XCTUnwrap(controller.pendingSleep)
    }

    func testSafeguardWithLidClosedWaitsForAgentsThenSleeps() throws {
        let controller = closedLidController()
        let end = try XCTUnwrap(controller.endDate)
        let pending = try startCheckpoint(controller)
        XCTAssertEqual(pending, PendingSleep(reason: .timerFinished, deadline: end.addingTimeInterval(1 + CheckpointPolicy.standardGrace)))
        XCTAssertEqual(checkpoint.begun, [pending])
        XCTAssertEqual(controller.sleepCountdown, CheckpointPolicy.standardGrace)
        XCTAssertTrue(controller.isActive)
        XCTAssertTrue(power.sleepDisabled)
        XCTAssertEqual(power.sleepNowCount, 0)

        controller.tick(at: pending.deadline.addingTimeInterval(-1))
        XCTAssertTrue(controller.isActive)

        let finishes = checkpoint.finishCount
        controller.tick(at: pending.deadline)
        XCTAssertFalse(controller.isActive)
        XCTAssertNil(controller.pendingSleep)
        XCTAssertEqual(controller.lastEnd?.reason, .timerFinished)
        XCTAssertFalse(power.sleepDisabled)
        XCTAssertEqual(power.sleepNowCount, 1)
        XCTAssertEqual(checkpoint.finishCount, finishes + 1)
        XCTAssertEqual(checkpoint.begun.count, 1)
    }

    func testHotMacGetsAShorterWindow() {
        let controller = closedLidController(.unlimited)
        monitor.current = monitor.current.with { $0.thermal = .serious }
        controller.tick(at: Date().addingTimeInterval(10))
        XCTAssertEqual(controller.pendingSleep?.reason, .thermal)
        XCTAssertEqual(controller.sleepCountdown, CheckpointPolicy.hotGrace)
    }

    func testHeatWindowEndsInSleepEvenIfTheMacCools() throws {
        let controller = closedLidController(.unlimited)
        monitor.current = monitor.current.with { $0.thermal = .serious }
        controller.tick(at: Date().addingTimeInterval(10))
        let pending = try XCTUnwrap(controller.pendingSleep)
        monitor.current = monitor.current.with { $0.thermal = .fair }
        controller.tick(at: pending.deadline.addingTimeInterval(-5))
        XCTAssertEqual(controller.pendingSleep, pending)
        controller.tick(at: pending.deadline)
        XCTAssertFalse(controller.isActive)
        XCTAssertEqual(controller.lastEnd?.reason, .thermal)
        XCTAssertEqual(power.sleepNowCount, 1)
    }

    func testCriticalHeatEndsTheWindowAtOnce() throws {
        let controller = closedLidController()
        let pending = try startCheckpoint(controller)
        monitor.current = monitor.current.with { $0.thermal = .critical }
        controller.tick(at: pending.deadline.addingTimeInterval(-50))
        XCTAssertFalse(controller.isActive)
        XCTAssertEqual(power.sleepNowCount, 1)
    }

    func testOpeningTheLidEndsTheWindowWithoutSleeping() throws {
        let controller = closedLidController()
        let pending = try startCheckpoint(controller)
        monitor.current = monitor.current.with { $0.lidClosed = false }
        controller.tick(at: pending.deadline.addingTimeInterval(-50))
        XCTAssertFalse(controller.isActive)
        XCTAssertNil(controller.pendingSleep)
        XCTAssertEqual(power.sleepNowCount, 0)
    }

    func testPluggingInCancelsABatteryWindow() {
        let controller = closedLidController(.unlimited)
        monitor.current = monitor.current.with { $0.battery = BatteryInfo(percent: 20, onBattery: true, charging: false) }
        controller.tick(at: Date().addingTimeInterval(10))
        XCTAssertEqual(controller.pendingSleep?.reason, .lowBattery(20))

        let finishes = checkpoint.finishCount
        monitor.current = monitor.current.with { $0.battery = BatteryInfo(percent: 20, onBattery: false, charging: true) }
        controller.tick(at: Date().addingTimeInterval(20))
        XCTAssertNil(controller.pendingSleep)
        XCTAssertTrue(controller.isActive)
        XCTAssertEqual(checkpoint.finishCount, finishes + 1)
        XCTAssertEqual(power.sleepNowCount, 0)
    }

    func testManualStopCancelsTheWindow() throws {
        let controller = closedLidController()
        _ = try startCheckpoint(controller)
        let finishes = checkpoint.finishCount
        controller.toggle()
        XCTAssertFalse(controller.isActive)
        XCTAssertNil(controller.pendingSleep)
        XCTAssertEqual(checkpoint.finishCount, finishes + 1)
        XCTAssertEqual(power.sleepNowCount, 0)
    }

    func testExtendingTheTimerCancelsItsWindow() throws {
        let controller = closedLidController()
        let pending = try startCheckpoint(controller)
        controller.extend()
        XCTAssertNil(controller.pendingSleep)
        controller.tick(at: pending.deadline.addingTimeInterval(60))
        XCTAssertTrue(controller.isActive)
        XCTAssertEqual(power.sleepNowCount, 0)
    }

    func testSwitchingCheckpointOffMidWindowSleepsNow() throws {
        let controller = closedLidController()
        let pending = try startCheckpoint(controller)
        controller.checkpointBeforeSleep = false
        controller.tick(at: pending.deadline.addingTimeInterval(-50))
        XCTAssertFalse(controller.isActive)
        XCTAssertEqual(power.sleepNowCount, 1)
    }

    func testFailedStopAfterTheWindowRetriesWithoutWaitingAgain() throws {
        let controller = closedLidController()
        let pending = try startCheckpoint(controller)
        power.shouldFail = true
        controller.tick(at: pending.deadline)
        controller.tick(at: pending.deadline.addingTimeInterval(1))
        XCTAssertTrue(controller.isActive)
        XCTAssertEqual(controller.pendingSleep, pending)
        XCTAssertEqual(power.setCalls, [true, false])

        power.shouldFail = false
        controller.tick(at: pending.deadline.addingTimeInterval(31))
        XCTAssertFalse(controller.isActive)
        XCTAssertNil(controller.pendingSleep)
        XCTAssertEqual(checkpoint.begun.count, 1)
        XCTAssertEqual(power.sleepNowCount, 1)
    }

    func testFailedStopAfterAHeatWindowRetriesEvenIfTheMacCooled() throws {
        let controller = closedLidController(.unlimited)
        monitor.current = monitor.current.with { $0.thermal = .serious }
        controller.tick(at: Date().addingTimeInterval(10))
        let pending = try XCTUnwrap(controller.pendingSleep)
        power.shouldFail = true
        controller.tick(at: pending.deadline)
        monitor.current = monitor.current.with { $0.thermal = .nominal }
        power.shouldFail = false
        controller.tick(at: pending.deadline.addingTimeInterval(31))
        XCTAssertFalse(controller.isActive)
        XCTAssertEqual(controller.lastEnd?.reason, .thermal)
        XCTAssertEqual(power.sleepNowCount, 1)
    }

    func testExtendingAfterAFailedStopGivesTheNextTripAWindow() throws {
        let controller = closedLidController()
        let pending = try startCheckpoint(controller)
        power.shouldFail = true
        controller.tick(at: pending.deadline)
        power.shouldFail = false
        controller.extend()
        XCTAssertNil(controller.pendingSleep)

        let end = try XCTUnwrap(controller.endDate)
        controller.tick(at: end.addingTimeInterval(1))
        XCTAssertEqual(controller.pendingSleep?.reason, .timerFinished)
        XCTAssertEqual(checkpoint.begun.count, 2)
        XCTAssertTrue(controller.isActive)
    }

    func testBatteryTickingBackUpAPercentKeepsTheWindow() {
        let controller = closedLidController(.unlimited)
        monitor.current = monitor.current.with { $0.battery.percent = 20 }
        controller.tick(at: Date().addingTimeInterval(10))
        let pending = controller.pendingSleep
        XCTAssertNotNil(pending)
        monitor.current = monitor.current.with { $0.battery.percent = 21 }
        controller.tick(at: Date().addingTimeInterval(20))
        monitor.current = monitor.current.with { $0.battery.percent = 20 }
        controller.tick(at: Date().addingTimeInterval(30))
        XCTAssertEqual(controller.pendingSleep, pending)
        XCTAssertEqual(checkpoint.begun.count, 1)
    }

    func testHeatRisingMidWindowBringsTheDeadlineForward() throws {
        let controller = closedLidController()
        let pending = try startCheckpoint(controller)
        let hotAt = pending.deadline.addingTimeInterval(-55)
        monitor.current = monitor.current.with { $0.thermal = .serious }
        controller.tick(at: hotAt)
        let sooner = PendingSleep(reason: .timerFinished, deadline: hotAt.addingTimeInterval(CheckpointPolicy.hotGrace))
        XCTAssertEqual(controller.pendingSleep, sooner)
        XCTAssertEqual(checkpoint.begun, [pending, sooner])

        controller.tick(at: hotAt.addingTimeInterval(1))
        XCTAssertEqual(controller.pendingSleep, sooner)
        controller.tick(at: sooner.deadline)
        XCTAssertFalse(controller.isActive)
        XCTAssertEqual(power.sleepNowCount, 1)
    }

    func testOpeningTheLidJustBeforeTheDeadlineDoesNotSleep() throws {
        // The snapshot refreshes every 5 s, so a tick at the deadline can still see the lid closed.
        // Dates in the past keep tick() from refreshing it.
        let controller = closedLidController(.unlimited)
        monitor.current = monitor.current.with { $0.thermal = .serious }
        controller.refreshSystem()
        controller.tick(at: Date().addingTimeInterval(-25))
        let pending = try XCTUnwrap(controller.pendingSleep)
        monitor.current = monitor.current.with { $0.lidClosed = false }
        controller.tick(at: pending.deadline)
        XCTAssertFalse(controller.isActive)
        XCTAssertEqual(power.sleepNowCount, 0)
    }

    func testQuitClearsTheWindowEvenForAnExternalSession() {
        power.sleepDisabled = true
        monitor.current = SystemSnapshot.healthy.with {
            $0.lidClosed = true
            $0.thermal = .serious
        }
        let controller = makeController()
        controller.syncOnLaunch()
        XCTAssertTrue(controller.isExternal)
        controller.tick(at: Date().addingTimeInterval(10))
        XCTAssertNotNil(controller.pendingSleep)

        let finishes = checkpoint.finishCount
        controller.restoreForQuit()
        XCTAssertEqual(checkpoint.finishCount, finishes + 1)
        XCTAssertTrue(power.sleepDisabled)
    }

    func testLaunchClearsAStaleWindow() {
        let controller = makeController()
        controller.syncOnLaunch()
        XCTAssertEqual(checkpoint.finishCount, 1)
    }

    func testWakingWithSleepRestoredElsewhereClearsTheWindow() throws {
        let controller = closedLidController()
        _ = try startCheckpoint(controller)
        power.sleepDisabled = false
        controller.resync()
        XCTAssertFalse(controller.isActive)
        XCTAssertNil(controller.pendingSleep)
    }
}
