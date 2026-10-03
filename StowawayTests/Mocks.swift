import Foundation
@testable import Stowaway

final class MockPower: PowerControlling {
    var sleepDisabled = false
    var shouldFail = false
    private(set) var setCalls: [Bool] = []
    private(set) var sleepNowCount = 0

    func isSleepDisabled() -> Bool { sleepDisabled }

    func setSleepDisabled(_ disabled: Bool, allowPrompt: Bool) throws {
        setCalls.append(disabled)
        if shouldFail { throw StowawayError.failed("pmset refused") }
        sleepDisabled = disabled
    }

    func sleepNow() { sleepNowCount += 1 }
}

final class MockMonitor: SystemMonitoring {
    var current: SystemSnapshot

    init(_ current: SystemSnapshot = .healthy) {
        self.current = current
    }

    func snapshot() -> SystemSnapshot { current }
}

final class MockAuthorizer: Authorizing {
    var installed: Bool
    var installError: Error?
    private(set) var installCalls = 0

    init(installed: Bool = true) {
        self.installed = installed
    }

    func isInstalled() -> Bool { installed }

    func install() throws {
        installCalls += 1
        if let installError { throw installError }
        installed = true
    }

    func uninstall() throws { installed = false }
}

extension SystemSnapshot {
    static let healthy = SystemSnapshot(
        battery: BatteryInfo(percent: 82, onBattery: true, charging: false),
        thermal: .nominal,
        lidClosed: false,
        externalDisplay: false
    )

    func with(_ change: (inout SystemSnapshot) -> Void) -> SystemSnapshot {
        var copy = self
        change(&copy)
        return copy
    }
}

func makeTestDefaults() -> UserDefaults {
    let name = "StowawayTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: name)!
    defaults.removePersistentDomain(forName: name)
    return defaults
}
