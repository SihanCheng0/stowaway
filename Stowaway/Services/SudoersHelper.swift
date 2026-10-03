import Foundation

protocol Authorizing {
    func isInstalled() -> Bool
    func install() throws
    func uninstall() throws
}

/// Manages `/etc/sudoers.d/stowaway`: a rule that lets the current user run exactly
/// `pmset -a disablesleep 0` and `pmset -a disablesleep 1` as root without a password.
struct SudoersHelper: Authorizing {
    static let rulePath = "/etc/sudoers.d/stowaway"

    let user: String

    init(user: String = NSUserName()) {
        self.user = user
    }

    /// macOS short names; anything else could break out of the sudoers line.
    static func isValidUsername(_ name: String) -> Bool {
        name.range(of: #"^[A-Za-z0-9_][A-Za-z0-9._-]{0,63}$"#, options: .regularExpression) != nil
    }

    static func ruleText(for user: String) -> String? {
        guard isValidUsername(user) else { return nil }
        let pmset = PowerManager.pmset
        return "\(user) ALL=(root) NOPASSWD: \(pmset) -a disablesleep 0, \(pmset) -a disablesleep 1"
    }

    /// Writes the rule to a temp file, validates it with `visudo`, and only then installs it.
    static func installScript(for user: String) -> String? {
        guard let rule = ruleText(for: user) else { return nil }
        let comment = "# Installed by Stowaway: lets \(user) toggle lid-closed sleep without a password."
        return "tmp=$(/usr/bin/mktemp)"
            + " && /usr/bin/printf '%s\\n' '\(comment)' '\(rule)' > \"$tmp\""
            + " && /usr/sbin/visudo -cf \"$tmp\" > /dev/null"
            + " && /bin/mkdir -p /etc/sudoers.d"
            + " && /usr/bin/install -m 0440 -o root -g wheel \"$tmp\" \(rulePath)"
            + "; rc=$?; /bin/rm -f \"$tmp\"; exit $rc"
    }

    func isInstalled() -> Bool {
        Shell.run("/usr/bin/sudo", ["-n", "-l", PowerManager.pmset, "-a", "disablesleep", "1"]).status == 0
    }

    func install() throws {
        guard let script = Self.installScript(for: user) else {
            throw StowawayError.failed("Unsupported user name “\(user)”.")
        }
        try AdminRunner.run(script)
        guard isInstalled() else {
            throw StowawayError.failed("The rule was installed but sudo doesn't accept it.")
        }
    }

    func uninstall() throws {
        try AdminRunner.run("/bin/rm -f \(Self.rulePath)")
    }
}

/// Runs a shell command as root behind the standard macOS administrator password dialog.
enum AdminRunner {
    static func source(for command: String) -> String {
        "do shell script \(quoted(command)) with prompt \"Stowaway needs your permission to change sleep settings.\" with administrator privileges"
    }

    /// An AppleScript string literal containing exactly `text`.
    static func quoted(_ text: String) -> String {
        let escaped = text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }

    static func run(_ command: String) throws {
        guard let script = NSAppleScript(source: source(for: command)) else {
            throw StowawayError.failed("Couldn't prepare the administrator prompt.")
        }
        var error: NSDictionary?
        script.executeAndReturnError(&error)
        guard let error else { return }
        if error[NSAppleScript.errorNumber] as? Int == -128 {
            throw StowawayError.cancelled
        }
        throw StowawayError.failed(error[NSAppleScript.errorMessage] as? String ?? "The administrator command failed.")
    }
}
