import Foundation

protocol PowerControlling {
    func isSleepDisabled() -> Bool
    /// `allowPrompt` lets it fall back to the admin password dialog when the sudo rule is missing.
    func setSleepDisabled(_ disabled: Bool, allowPrompt: Bool) throws
    func sleepNow()
}

enum StowawayError: LocalizedError, Equatable {
    case cancelled
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .cancelled: return "Cancelled."
        case .failed(let message): return message
        }
    }
}

/// Reads the `SleepDisabled` flag from `pmset -g` output. The line only appears under
/// "System-wide power settings" once the flag has been set.
enum PmsetParser {
    static func sleepDisabled(in output: String) -> Bool {
        for line in output.split(whereSeparator: \.isNewline) {
            let fields = line.split(whereSeparator: \.isWhitespace)
            if fields.first == "SleepDisabled" {
                return fields.dropFirst().first == "1"
            }
        }
        return false
    }
}

struct PowerManager: PowerControlling {
    static let pmset = "/usr/bin/pmset"

    func isSleepDisabled() -> Bool {
        PmsetParser.sleepDisabled(in: Shell.run(Self.pmset, ["-g"]).output)
    }

    func setSleepDisabled(_ disabled: Bool, allowPrompt: Bool) throws {
        let arguments = ["-a", "disablesleep", disabled ? "1" : "0"]
        if Shell.run("/usr/bin/sudo", ["-n", Self.pmset] + arguments).status != 0 {
            guard allowPrompt else {
                throw StowawayError.failed("Stowaway isn't authorized to change sleep settings.")
            }
            try AdminRunner.run(([Self.pmset] + arguments).joined(separator: " "))
        }
        guard isSleepDisabled() == disabled else {
            throw StowawayError.failed("macOS didn't apply the sleep change.")
        }
    }

    /// Doesn't need root.
    func sleepNow() {
        Shell.run(Self.pmset, ["sleepnow"])
    }
}
