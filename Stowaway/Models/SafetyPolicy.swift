import Foundation

enum EndReason: Equatable {
    case manual
    case timerFinished
    case lowBattery(Int)
    case thermal
    case recovered
    case quit

    /// Ended by a safeguard rather than by you, so a closed Mac should go to sleep right away.
    var isAutomatic: Bool {
        switch self {
        case .timerFinished, .lowBattery, .thermal: return true
        case .manual, .recovered, .quit: return false
        }
    }

    /// Stable machine-readable name, used by checkpoint hooks.
    var code: String {
        switch self {
        case .manual: return "manual"
        case .timerFinished: return "timer"
        case .lowBattery: return "battery"
        case .thermal: return "heat"
        case .recovered: return "recovered"
        case .quit: return "quit"
        }
    }

    var summary: String {
        switch self {
        case .manual: return "turned off"
        case .timerFinished: return "timer finished"
        case .lowBattery(let percent): return "battery at \(percent)%"
        case .thermal: return "Mac running hot"
        case .recovered: return "recovered after Stowaway quit unexpectedly"
        case .quit: return "Stowaway quit"
        }
    }
}

struct SafetySettings: Equatable {
    static let batteryFloorRange = 10...50

    var batteryFloor: Int
    var thermalGuard: Bool
}

enum SafetyPolicy {
    /// The reason a session must end now, or nil if it may continue.
    static func evaluate(now: Date, endDate: Date?, system: SystemSnapshot, settings: SafetySettings) -> EndReason? {
        if let endDate, now >= endDate {
            return .timerFinished
        }
        if settings.thermalGuard, system.thermal == .serious || system.thermal == .critical {
            return .thermal
        }
        if system.battery.onBattery, let percent = system.battery.percent, percent <= settings.batteryFloor {
            return .lowBattery(percent)
        }
        return nil
    }
}
