import Foundation

enum AwakeDuration: Int, CaseIterable, Identifiable {
    case thirtyMinutes = 1800
    case oneHour = 3600
    case twoHours = 7200
    case fourHours = 14400
    case unlimited = 0

    var id: Int { rawValue }

    var interval: TimeInterval? {
        self == .unlimited ? nil : TimeInterval(rawValue)
    }

    var label: String {
        switch self {
        case .thirtyMinutes: return "30m"
        case .oneHour: return "1h"
        case .twoHours: return "2h"
        case .fourHours: return "4h"
        case .unlimited: return "∞"
        }
    }

    var spokenLabel: String {
        switch self {
        case .thirtyMinutes: return "30 minutes"
        case .oneHour: return "1 hour"
        case .twoHours: return "2 hours"
        case .fourHours: return "4 hours"
        case .unlimited: return "No time limit"
        }
    }
}

enum Countdown {
    /// "1:42:07", or "42:07" under an hour. Rounds up so the first second shows the full duration.
    static func clock(_ remaining: TimeInterval) -> String {
        let total = Int(max(0, remaining).rounded(.up))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, seconds)
            : String(format: "%d:%02d", minutes, seconds)
    }

    /// Menu bar form, hours:minutes ("1:42"). Never shows "0:00" while time is left.
    static func compact(_ remaining: TimeInterval) -> String {
        let minutes = remaining > 0 ? max(1, Int(remaining / 60)) : 0
        return String(format: "%d:%02d", minutes / 60, minutes % 60)
    }
}
