import XCTest
@testable import Stowaway

final class ClaudeHookInstallerTests: XCTestCase {
    private var home: URL!
    private var installer: ClaudeHookInstaller!

    override func setUpWithError() throws {
        home = FileManager.default.temporaryDirectory.appendingPathComponent("StowawayTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        installer = ClaudeHookInstaller(home: home)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: home)
    }

    private func writeSettings(_ text: String) throws {
        try FileManager.default.createDirectory(at: installer.settingsFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: installer.settingsFile)
    }

    private func settings(at url: URL? = nil) throws -> [String: Any] {
        let data = try Data(contentsOf: url ?? installer.settingsFile)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func postToolUse() throws -> [[String: Any]] {
        try XCTUnwrap((settings()["hooks"] as? [String: Any])?["PostToolUse"] as? [[String: Any]])
    }

    // MARK: - Installing

    func testInstallsIntoMissingSettings() throws {
        XCTAssertFalse(installer.isClaudeCodePresent)
        try installer.install()
        XCTAssertTrue(installer.isInstalled)
        XCTAssertTrue(installer.isClaudeCodePresent)
        let entries = try postToolUse()
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0]["matcher"] as? String, "*")
        let hook = try XCTUnwrap((entries[0]["hooks"] as? [[String: Any]])?.first)
        XCTAssertEqual(hook["type"] as? String, "command")
        XCTAssertEqual(hook["command"] as? String, ClaudeHookInstaller.command)
        XCTAssertEqual(hook["timeout"] as? Int, 10)
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: installer.scriptFile.path))
    }

    func testTreatsBlankSettingsAsNew() throws {
        try writeSettings(" \n")
        try installer.install()
        XCTAssertTrue(installer.isInstalled)
    }

    func testKeepsOtherSettingsAndHooksAndBacksUp() throws {
        let original = #"{"model":"opus","hooks":{"PostToolUse":[{"matcher":"Edit","hooks":[{"type":"command","command":"prettier --write"}]}],"Stop":[{"hooks":[{"type":"command","command":"say done"}]}]}}"#
        try writeSettings(original)
        try installer.install()

        let updated = try settings()
        XCTAssertEqual(updated["model"] as? String, "opus")
        let hooks = try XCTUnwrap(updated["hooks"] as? [String: Any])
        XCTAssertEqual((hooks["Stop"] as? [Any])?.count, 1)
        let entries = try postToolUse()
        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(entries[0]["matcher"] as? String, "Edit")
        let backup = installer.settingsFile.appendingPathExtension("stowaway-backup")
        XCTAssertEqual(try String(contentsOf: backup, encoding: .utf8), original)
    }

    func testNeverAddsItTwice() throws {
        try installer.install()
        try installer.install()
        XCTAssertEqual(try postToolUse().count, 1)
    }

    func testLeavesInvalidSettingsAlone() throws {
        let original = "{\n  \"model\": \"opus\", // my favorite\n}\n"
        try writeSettings(original)
        XCTAssertThrowsError(try installer.install()) { error in
            guard case ClaudeHookInstaller.InstallError.unreadableSettings(let snippet) = error else {
                return XCTFail("unexpected error \(error)")
            }
            let pasted = try? JSONSerialization.jsonObject(with: Data(snippet.utf8)) as? [String: Any]
            XCTAssertTrue(ClaudeHookInstaller.containsHook(pasted ?? [:]))
        }
        XCTAssertEqual(try String(contentsOf: installer.settingsFile, encoding: .utf8), original)
        XCTAssertFalse(installer.isInstalled)
        // The script is still written, so the pasted snippet works.
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: installer.scriptFile.path))
    }

    func testLeavesAnUnreadableFileAlone() throws {
        let original = #"{"model":"opus"}"#
        try writeSettings(original)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: installer.settingsFile.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: installer.settingsFile.path) }
        XCTAssertThrowsError(try installer.install())
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: installer.settingsFile.path)
        XCTAssertEqual(try String(contentsOf: installer.settingsFile, encoding: .utf8), original)
    }

    func testLeavesASymlinkToAMissingFileAlone() throws {
        let missing = home.appendingPathComponent("unmounted/claude-settings.json")
        try FileManager.default.createDirectory(at: installer.settingsFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: installer.settingsFile, withDestinationURL: missing)
        XCTAssertThrowsError(try installer.install())
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: installer.settingsFile.path), missing.path)
    }

    func testLeavesUnexpectedHookShapesAlone() throws {
        for original in [#"{"hooks":[]}"#, #"{"hooks":{"PostToolUse":{}}}"#] {
            try writeSettings(original)
            XCTAssertThrowsError(try installer.install())
            XCTAssertEqual(try String(contentsOf: installer.settingsFile, encoding: .utf8), original)
        }
    }

    func testWritesThroughASymlink() throws {
        let real = home.appendingPathComponent("dotfiles/claude-settings.json")
        try FileManager.default.createDirectory(at: real.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(#"{"model":"opus"}"#.utf8).write(to: real)
        try FileManager.default.createDirectory(at: installer.settingsFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: installer.settingsFile, withDestinationURL: real)

        try installer.install()
        let attributes = try FileManager.default.attributesOfItem(atPath: installer.settingsFile.path)
        XCTAssertEqual(attributes[.type] as? FileAttributeType, .typeSymbolicLink)
        XCTAssertTrue(ClaudeHookInstaller.containsHook(try settings(at: real)))
        XCTAssertEqual(try settings(at: real)["model"] as? String, "opus")
    }

    func testKeepsTheFilesPermissions() throws {
        try writeSettings(#"{"env":{"ANTHROPIC_API_KEY":"secret"}}"#)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: installer.settingsFile.path)
        try installer.install()
        let backup = installer.settingsFile.appendingPathExtension("stowaway-backup")
        for file in [installer.settingsFile, backup] {
            let permissions = try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? Int
            XCTAssertEqual(permissions, 0o600, file.lastPathComponent)
        }
    }

    func testWritesJSONTheWayClaudeCodeDoes() throws {
        let parsed = try JSONSerialization.jsonObject(with: Data(#"{"b":0.7,"a":[true,30,"say \"hi\"\n"],"c":{},"d":null,"e":[],"f":1.0}"#.utf8))
        XCTAssertEqual(ClaudeHookInstaller.format(parsed), """
        {
          "a": [
            true,
            30,
            "say \\"hi\\"\\n"
          ],
          "b": 0.7,
          "c": {},
          "d": null,
          "e": [],
          "f": 1
        }
        """)
        let reparsed = try JSONSerialization.jsonObject(with: Data(ClaudeHookInstaller.format(parsed).utf8))
        XCTAssertEqual(reparsed as? NSDictionary, parsed as? NSDictionary)
    }

    func testUpdatesTheScriptOnlyWhenTheHookIsInUse() throws {
        installer.updateScriptIfInstalled()
        XCTAssertFalse(FileManager.default.fileExists(atPath: installer.scriptFile.path))

        try installer.install()
        try FileManager.default.removeItem(at: installer.scriptFile)
        XCTAssertFalse(installer.isInstalled)
        installer.updateScriptIfInstalled()
        XCTAssertTrue(installer.isInstalled)
    }

    // MARK: - The hook script

    /// Runs the hook the way Claude Code does: the settings command through a shell, JSON on stdin.
    private func runHook(session: String) throws -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", ClaudeHookInstaller.command]
        process.environment = ["HOME": home.path, "PATH": "/usr/bin:/bin"]
        let input = Pipe()
        let output = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()
        // A tool input that mentions session_id itself mustn't confuse the hook.
        let payload = #"{"session_id":"\#(session)","hook_event_name":"PostToolUse","tool_name":"Bash","tool_input":{"command":"echo \"session_id\":\"other\""}}"#
        input.fileHandleForWriting.write(Data(payload.utf8))
        try input.fileHandleForWriting.close()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(decoding: data, as: UTF8.self))
    }

    private func announceSleep(in seconds: TimeInterval) {
        let hook = CheckpointHook(
            directory: home.appendingPathComponent(".config/stowaway"),
            logFile: home.appendingPathComponent("before-sleep.log")
        )
        hook.begin(PendingSleep(reason: .lowBattery(19), deadline: Date().addingTimeInterval(seconds)), system: .healthy)
    }

    func testHookIsSilentUntilSleepIsComing() throws {
        try installer.install()
        let result = try runHook(session: "s1")
        XCTAssertEqual(result.status, 0)
        XCTAssertEqual(result.output, "")
    }

    func testHookAsksEachSessionOnce() throws {
        try installer.install()
        announceSleep(in: 60)

        let first = try runHook(session: "s1")
        XCTAssertEqual(first.status, 0)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(first.output.utf8)) as? [String: Any], first.output)
        let specific = try XCTUnwrap(json["hookSpecificOutput"] as? [String: Any])
        XCTAssertEqual(specific["hookEventName"] as? String, "PostToolUse")
        let context = try XCTUnwrap(specific["additionalContext"] as? String)
        XCTAssertTrue(context.hasPrefix("Stowaway: this Mac goes to sleep in about "), context)
        XCTAssertTrue(context.contains("seconds (battery at 19%). Checkpoint now."), context)
        XCTAssertTrue(context.contains("$(git stash create)"), context)
        XCTAssertNotNil(json["systemMessage"] as? String)
        XCTAssertTrue(FileManager.default.fileExists(atPath: home.appendingPathComponent(".config/stowaway/notified").path))

        XCTAssertEqual(try runHook(session: "s1").output, "")
        XCTAssertFalse(try runHook(session: "s2").output.isEmpty)
    }

    func testHookIgnoresAWindowThatAlreadyEnded() throws {
        try installer.install()
        announceSleep(in: -5)
        XCTAssertEqual(try runHook(session: "s1").output, "")
    }

    func testLeftoverHookEntryIsHarmless() throws {
        // Settings still point at the hook, but the script is gone (e.g. after uninstalling Stowaway).
        let result = try runHook(session: "s1")
        XCTAssertEqual(result.status, 0)
        XCTAssertEqual(result.output, "")
    }
}
