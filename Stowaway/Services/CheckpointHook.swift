import Foundation

protocol CheckpointHooking {
    /// Announces the coming sleep, or a sooner deadline, and starts the user's before-sleep script once per window.
    func begin(_ pending: PendingSleep, system: SystemSnapshot)
    /// Stops the script if it's still running and withdraws the announcement.
    func finish()
}

/// Announces a coming sleep in `~/.config/stowaway/sleep-pending.json`, which agent hooks read,
/// and runs the optional `~/.config/stowaway/before-sleep` script.
final class CheckpointHook: CheckpointHooking {
    static let defaultDirectory = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".config/stowaway", isDirectory: true)
    static let defaultLogFile = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/Stowaway/before-sleep.log")

    let directory: URL
    let logFile: URL
    var pendingFile: URL { directory.appendingPathComponent("sleep-pending.json") }
    var scriptFile: URL { directory.appendingPathComponent("before-sleep") }
    /// Where agent hooks record which sessions they've already told.
    var notifiedDirectory: URL { directory.appendingPathComponent("notified", isDirectory: true) }

    private(set) var process: Process?

    init(directory: URL = defaultDirectory, logFile: URL = defaultLogFile) {
        self.directory = directory
        self.logFile = logFile
    }

    func begin(_ pending: PendingSleep, system: SystemSnapshot) {
        let environment = Self.environment(for: pending, system: system)
        writePendingFile(environment)
        if process == nil {
            runScript(environment)
        }
    }

    func finish() {
        if let process, process.isRunning {
            process.terminate()
        }
        process = nil
        try? FileManager.default.removeItem(at: pendingFile)
        try? FileManager.default.removeItem(at: notifiedDirectory)
    }

    /// Everything a hook needs, as environment variables. The pending file holds the same values.
    static func environment(for pending: PendingSleep, system: SystemSnapshot) -> [String: String] {
        let seconds = max(0, Int(pending.deadline.timeIntervalSinceNow.rounded()))
        var values = [
            "STOWAWAY_REASON": pending.reason.code,
            "STOWAWAY_SUMMARY": pending.reason.summary,
            "STOWAWAY_DEADLINE": String(Int(pending.deadline.timeIntervalSince1970)),
            "STOWAWAY_SECONDS": String(seconds),
            "STOWAWAY_LID": system.lidClosed ? "closed" : "open",
        ]
        if let percent = system.battery.percent {
            values["STOWAWAY_BATTERY"] = String(percent)
        }
        return values
    }

    private func writePendingFile(_ environment: [String: String]) {
        let json: [String: Any] = [
            "reason": environment["STOWAWAY_REASON"] ?? "",
            "summary": environment["STOWAWAY_SUMMARY"] ?? "",
            "deadline": Int(environment["STOWAWAY_DEADLINE"] ?? "") ?? 0,
            "seconds": Int(environment["STOWAWAY_SECONDS"] ?? "") ?? 0,
            "lid": environment["STOWAWAY_LID"] ?? "",
            "battery": environment["STOWAWAY_BATTERY"].flatMap(Int.init).map { $0 as Any } ?? NSNull(),
        ]
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try JSONSerialization.data(withJSONObject: json, options: [.sortedKeys])
            try data.write(to: pendingFile, options: .atomic)
        } catch {
            NSLog("Stowaway: couldn't write %@: %@", pendingFile.path, String(describing: error))
        }
    }

    private func runScript(_ environment: [String: String]) {
        guard FileManager.default.isExecutableFile(atPath: scriptFile.path) else { return }
        let process = Process()
        // A login shell, so the script sees the same PATH as in Terminal (Homebrew, git, claude…).
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", "exec \"$0\"", scriptFile.path]
        process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, new in new }
        process.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser
        process.standardInput = FileHandle.nullDevice
        if let log = openLog(header: environment["STOWAWAY_SUMMARY"] ?? "") {
            process.standardOutput = log
            process.standardError = log
        }
        do {
            try process.run()
            self.process = process
        } catch {
            NSLog("Stowaway: couldn't run %@: %@", scriptFile.path, String(describing: error))
        }
    }

    private func openLog(header: String) -> FileHandle? {
        let manager = FileManager.default
        try? manager.createDirectory(at: logFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        if !manager.fileExists(atPath: logFile.path) {
            manager.createFile(atPath: logFile.path, contents: nil)
        }
        guard let handle = try? FileHandle(forWritingTo: logFile) else { return nil }
        // The throwing forms: the older calls raise Objective-C exceptions on a full disk, and crash.
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: Data("\n== \(Date().formatted(.iso8601)) before-sleep (\(header))\n".utf8))
        return handle
    }
}
