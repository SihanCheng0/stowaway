import XCTest
@testable import Stowaway

final class CheckpointHookTests: XCTestCase {
    private var root: URL!
    private var hook: CheckpointHook!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("StowawayTests-\(UUID().uuidString)")
        hook = CheckpointHook(
            directory: root.appendingPathComponent("config"),
            logFile: root.appendingPathComponent("logs/before-sleep.log")
        )
    }

    override func tearDownWithError() throws {
        hook.finish()
        try? FileManager.default.removeItem(at: root)
    }

    private func makePending() -> PendingSleep {
        PendingSleep(reason: .lowBattery(18), deadline: Date().addingTimeInterval(60))
    }

    private func pendingJSON() throws -> [String: Any] {
        let data = try Data(contentsOf: hook.pendingFile)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func installScript(_ body: String) throws {
        try FileManager.default.createDirectory(at: hook.directory, withIntermediateDirectories: true)
        try Data(("#!/bin/sh\n" + body + "\n").utf8).write(to: hook.scriptFile)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: hook.scriptFile.path)
    }

    private func waitForFile(_ url: URL, timeout: TimeInterval = 10) throws -> String {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let text = try? String(contentsOf: url, encoding: .utf8), !text.isEmpty { return text }
            Thread.sleep(forTimeInterval: 0.05)
        }
        XCTFail("\(url.lastPathComponent) never appeared")
        throw CocoaError(.fileReadNoSuchFile)
    }

    func testAnnouncesTheComingSleep() throws {
        let pending = makePending()
        hook.begin(pending, system: SystemSnapshot.healthy.with {
            $0.lidClosed = true
            $0.battery.percent = 18
        })
        let json = try pendingJSON()
        XCTAssertEqual(json["reason"] as? String, "battery")
        XCTAssertEqual(json["summary"] as? String, "battery at 18%")
        XCTAssertEqual(json["deadline"] as? Int, Int(pending.deadline.timeIntervalSince1970))
        XCTAssertEqual(json["lid"] as? String, "closed")
        XCTAssertEqual(json["battery"] as? Int, 18)

        hook.finish()
        XCTAssertFalse(FileManager.default.fileExists(atPath: hook.pendingFile.path))
    }

    func testMacWithoutBatteryWritesNull() throws {
        hook.begin(makePending(), system: SystemSnapshot.healthy.with { $0.battery = .none })
        XCTAssertTrue(try pendingJSON()["battery"] is NSNull)
    }

    func testFinishClearsWhichSessionsWereTold() throws {
        hook.begin(makePending(), system: .healthy)
        try FileManager.default.createDirectory(
            at: hook.notifiedDirectory.appendingPathComponent("123-session"),
            withIntermediateDirectories: true
        )
        hook.finish()
        XCTAssertFalse(FileManager.default.fileExists(atPath: hook.notifiedDirectory.path))
    }

    func testRunsTheBeforeSleepScriptWithDetails() throws {
        let output = root.appendingPathComponent("env.txt")
        try installScript(#"echo "$STOWAWAY_REASON $STOWAWAY_SECONDS $STOWAWAY_LID $STOWAWAY_BATTERY" > "\#(output.path)""#)
        hook.begin(makePending(), system: SystemSnapshot.healthy.with { $0.lidClosed = true })
        let fields = try waitForFile(output).split(separator: " ").map(String.init)
        XCTAssertEqual(fields.count, 4)
        XCTAssertEqual(fields.first, "battery")
        XCTAssertTrue((50...60).contains(Int(fields[1]) ?? -1), "seconds: \(fields[1])")
        XCTAssertEqual(fields[2], "closed")
        XCTAssertEqual(fields[3].trimmingCharacters(in: .whitespacesAndNewlines), "82")
    }

    func testLogsTheScriptsOutput() throws {
        try installScript("echo checkpointed")
        hook.begin(makePending(), system: .healthy)
        let process = try XCTUnwrap(hook.process)
        process.waitUntilExit()
        let log = try String(contentsOf: hook.logFile, encoding: .utf8)
        XCTAssertTrue(log.contains("before-sleep (battery at 18%)"), log)
        XCTAssertTrue(log.contains("checkpointed"), log)
    }

    func testFinishStopsAScriptThatRunsPastTheDeadline() throws {
        let started = root.appendingPathComponent("started")
        try installScript(#"echo yes > "\#(started.path)"; exec sleep 30"#)
        hook.begin(makePending(), system: .healthy)
        _ = try waitForFile(started)
        let process = try XCTUnwrap(hook.process)
        hook.finish()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationReason, .uncaughtSignal)
    }

    func testASoonerDeadlineIsAnnouncedButTheScriptRunsOnce() throws {
        let started = root.appendingPathComponent("started")
        try installScript(#"echo yes > "\#(started.path)"; exec sleep 30"#)
        hook.begin(makePending(), system: .healthy)
        _ = try waitForFile(started)
        let process = try XCTUnwrap(hook.process)

        let sooner = PendingSleep(reason: .lowBattery(18), deadline: Date().addingTimeInterval(20))
        hook.begin(sooner, system: .healthy)
        XCTAssertTrue(hook.process === process)
        XCTAssertEqual(try pendingJSON()["deadline"] as? Int, Int(sooner.deadline.timeIntervalSince1970))
    }

    func testSkipsAScriptThatIsNotExecutable() throws {
        try installScript("echo hi")
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: hook.scriptFile.path)
        hook.begin(makePending(), system: .healthy)
        XCTAssertNil(hook.process)
        XCTAssertTrue(FileManager.default.fileExists(atPath: hook.pendingFile.path))
    }
}
