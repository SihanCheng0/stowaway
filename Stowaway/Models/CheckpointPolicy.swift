import Foundation

/// A safeguard has tripped; the Mac stays awake until `deadline` so agents can checkpoint.
struct PendingSleep: Equatable {
    let reason: EndReason
    let deadline: Date
}

enum CheckpointPolicy {
    static let standardGrace: TimeInterval = 60
    static let hotGrace: TimeInterval = 20

    /// How long to stay awake for agents to checkpoint before a safeguard puts the Mac to sleep.
    /// Zero when the Mac won't sleep afterwards anyway, or is critically hot.
    static func grace(for reason: EndReason, system: SystemSnapshot) -> TimeInterval {
        guard reason.isAutomatic, system.wouldSleep, system.thermal != .critical else { return 0 }
        if reason == .thermal || system.thermal == .serious { return hotGrace }
        return standardGrace
    }
}
