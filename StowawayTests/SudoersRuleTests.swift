import XCTest
@testable import Stowaway

final class SudoersRuleTests: XCTestCase {
    func testRuleAllowsOnlyDisablesleep() {
        XCTAssertEqual(
            SudoersHelper.ruleText(for: "nyx"),
            "nyx ALL=(root) NOPASSWD: /usr/bin/pmset -a disablesleep 0, /usr/bin/pmset -a disablesleep 1"
        )
    }

    func testAcceptsTypicalUsernames() {
        for name in ["sihancheng", "john.doe", "dev_1", "a-b"] {
            XCTAssertNotNil(SudoersHelper.ruleText(for: name), name)
        }
    }

    func testRejectsUnsafeUsernames() {
        for name in ["", "a b", "x'; rm -rf /", "root ALL=(ALL)", "-flag", "a\nb", "%admin", "#0"] {
            XCTAssertNil(SudoersHelper.ruleText(for: name), name)
            XCTAssertNil(SudoersHelper.installScript(for: name), name)
        }
    }

    func testInstallScriptValidatesBeforeInstalling() throws {
        let script = try XCTUnwrap(SudoersHelper.installScript(for: "nyx"))
        let validate = try XCTUnwrap(script.range(of: "/usr/sbin/visudo -cf"))
        let install = try XCTUnwrap(script.range(of: "/usr/bin/install -m 0440 -o root -g wheel"))
        XCTAssertLessThan(validate.lowerBound, install.lowerBound)
        XCTAssertTrue(script.contains(SudoersHelper.rulePath))
        XCTAssertTrue(script.contains("/bin/rm -f \"$tmp\""))
    }
}

/// Compiles and evaluates AppleScript string literals only. Nothing is run as root.
final class AdminRunnerTests: XCTestCase {
    func testInstallScriptSurvivesAppleScriptQuoting() throws {
        let command = try XCTUnwrap(SudoersHelper.installScript(for: "nyx"))
        var error: NSDictionary?
        let result = NSAppleScript(source: "return " + AdminRunner.quoted(command))?.executeAndReturnError(&error)
        XCTAssertNil(error)
        XCTAssertEqual(result?.stringValue, command)
    }

    func testAdminSourceCompiles() throws {
        let command = try XCTUnwrap(SudoersHelper.installScript(for: "nyx"))
        var error: NSDictionary?
        let script = try XCTUnwrap(NSAppleScript(source: AdminRunner.source(for: command)))
        XCTAssertTrue(script.compileAndReturnError(&error), "\(error ?? [:])")
    }
}
