import Foundation

/// Adds Stowaway's checkpoint hook to Claude Code's user settings (`~/.claude/settings.json`).
/// The hook runs after every tool call and stays silent unless Stowaway is about to put the Mac to sleep.
struct ClaudeHookInstaller {
    enum InstallError: LocalizedError, Equatable {
        /// settings.json can't be merged safely, so it's left alone. `snippet` is the hook to paste in by hand.
        case unreadableSettings(snippet: String)

        var errorDescription: String? {
            "Stowaway couldn't safely update ~/.claude/settings.json, so it left it alone. The hook is on your clipboard to paste in."
        }
    }

    /// Identifies Stowaway's hook among the user's other hooks.
    static let marker = "stowaway/claude-code-hook.sh"
    /// Does nothing if the script is gone (e.g. after `brew uninstall --zap`), so a leftover entry never errors.
    static let command =
        #"[ -x "$HOME/.config/stowaway/claude-code-hook.sh" ] && exec "$HOME/.config/stowaway/claude-code-hook.sh"; cat >/dev/null"#

    let settingsFile: URL
    let scriptFile: URL

    init(home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        settingsFile = home.appendingPathComponent(".claude/settings.json")
        scriptFile = home.appendingPathComponent(".config/stowaway/claude-code-hook.sh")
    }

    /// Claude Code has been set up on this Mac.
    var isClaudeCodePresent: Bool {
        FileManager.default.fileExists(atPath: settingsFile.deletingLastPathComponent().path)
    }

    var isInstalled: Bool {
        FileManager.default.isExecutableFile(atPath: scriptFile.path) && settingsContainHook
    }

    /// Writes the hook script and merges the hook into settings.json, keeping a backup of the old file.
    func install() throws {
        try writeScript()
        // Write through a symlink (dotfile managers link settings.json) instead of replacing it.
        let file = settingsFile.resolvingSymlinksInPath()
        let existing = try readSettings(at: file)
        var settings: [String: Any] = [:]
        if let existing, !Self.isBlank(existing) {
            guard let object = try? JSONSerialization.jsonObject(with: existing) as? [String: Any] else {
                throw InstallError.unreadableSettings(snippet: Self.snippet)
            }
            settings = object
        }
        guard let merged = try Self.merged(settings) else { return }

        let manager = FileManager.default
        try manager.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        // settings.json can hold API keys under "env", so the new file and the backup keep its permissions.
        let permissions = (try? manager.attributesOfItem(atPath: file.path))?[.posixPermissions]
        if let existing {
            let backup = file.appendingPathExtension("stowaway-backup")
            try existing.write(to: backup, options: .atomic)
            if let permissions { try manager.setAttributes([.posixPermissions: permissions], ofItemAtPath: backup.path) }
        }
        try Data((Self.format(merged) + "\n").utf8).write(to: file, options: .atomic)
        if let permissions { try manager.setAttributes([.posixPermissions: permissions], ofItemAtPath: file.path) }
    }

    /// Keeps the script current after an app update, if the hook is in use.
    func updateScriptIfInstalled() {
        guard settingsContainHook else { return }
        try? writeScript()
    }

    // MARK: - Merging

    /// `settings` with Stowaway's hook added, or nil if it's already there.
    static func merged(_ settings: [String: Any]) throws -> [String: Any]? {
        guard !containsHook(settings) else { return nil }
        if let hooks = settings["hooks"], !(hooks is [String: Any]) {
            throw InstallError.unreadableSettings(snippet: snippet)
        }
        var hooks = settings["hooks"] as? [String: Any] ?? [:]
        if let entries = hooks["PostToolUse"], !(entries is [Any]) {
            throw InstallError.unreadableSettings(snippet: snippet)
        }
        var settings = settings
        hooks["PostToolUse"] = (hooks["PostToolUse"] as? [Any] ?? []) + [entry]
        settings["hooks"] = hooks
        return settings
    }

    static func containsHook(_ settings: [String: Any]) -> Bool {
        guard let events = settings["hooks"] as? [String: Any] else { return false }
        return events.values.contains { groups in
            (groups as? [[String: Any]] ?? []).contains { group in
                (group["hooks"] as? [[String: Any]] ?? []).contains { hook in
                    (hook["command"] as? String)?.contains(marker) == true
                }
            }
        }
    }

    static var entry: [String: Any] {
        ["matcher": "*", "hooks": [["type": "command", "command": command, "timeout": 10]]]
    }

    /// The settings.json fragment, for pasting in by hand.
    static var snippet: String {
        format(["hooks": ["PostToolUse": [entry]]])
    }

    /// JSON in the style Claude Code writes (`JSON.stringify(value, null, 2)`), with keys sorted
    /// because parsing loses their order. JSONSerialization would print 0.7 as 0.69999999999999996.
    static func format(_ value: Any, indent: String = "") -> String {
        let inner = indent + "  "
        switch value {
        case let dictionary as [String: Any]:
            guard !dictionary.isEmpty else { return "{}" }
            let members = dictionary.keys.sorted().map { inner + quote($0) + ": " + format(dictionary[$0]!, indent: inner) }
            return "{\n" + members.joined(separator: ",\n") + "\n" + indent + "}"
        case let array as [Any]:
            guard !array.isEmpty else { return "[]" }
            return "[\n" + array.map { inner + format($0, indent: inner) }.joined(separator: ",\n") + "\n" + indent + "]"
        case let string as String:
            return quote(string)
        case let number as NSNumber:
            if CFGetTypeID(number) == CFBooleanGetTypeID() { return number.boolValue ? "true" : "false" }
            if CFNumberIsFloatType(number) {
                let double = number.doubleValue
                guard double.isFinite else { return "null" }
                return double == double.rounded() && abs(double) < 1e15 ? String(Int64(double)) : "\(double)"
            }
            return number.stringValue
        default:
            return "null"
        }
    }

    private static func quote(_ string: String) -> String {
        var result = "\""
        for scalar in string.unicodeScalars {
            switch scalar {
            case "\"": result += "\\\""
            case "\\": result += "\\\\"
            case "\n": result += "\\n"
            case "\r": result += "\\r"
            case "\t": result += "\\t"
            case _ where scalar.value < 0x20: result += String(format: "\\u%04x", scalar.value)
            default: result.unicodeScalars.append(scalar)
            }
        }
        return result + "\""
    }

    // MARK: - Private

    /// The current file, or nil if there's none yet. Anything unreadable, including a symlink whose
    /// target is missing, throws instead of being treated as empty and overwritten.
    private func readSettings(at file: URL) throws -> Data? {
        do {
            return try Data(contentsOf: file)
        } catch CocoaError.fileReadNoSuchFile where (try? FileManager.default.destinationOfSymbolicLink(atPath: settingsFile.path)) == nil {
            return nil
        } catch {
            throw InstallError.unreadableSettings(snippet: Self.snippet)
        }
    }

    private var settingsContainHook: Bool {
        guard let data = try? Data(contentsOf: settingsFile),
              let settings = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return false }
        return Self.containsHook(settings)
    }

    private func writeScript() throws {
        let manager = FileManager.default
        try manager.createDirectory(at: scriptFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(Self.script.utf8).write(to: scriptFile, options: .atomic)
        try manager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptFile.path)
    }

    private static func isBlank(_ data: Data) -> Bool {
        String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Claude Code passes the hook's input as JSON on stdin and reads `additionalContext` from the
    /// JSON it prints. Each session is told once per window; `mkdir` makes that atomic when tools run in parallel.
    static let script = #"""
    #!/bin/sh
    # Stowaway's Claude Code hook. Stowaway writes and updates this file.
    # When Stowaway is about to put this Mac to sleep, it asks each Claude Code session,
    # once, to checkpoint. The rest of the time it exits right away and prints nothing.
    dir="$HOME/.config/stowaway"
    pending="$dir/sleep-pending.json"
    if [ ! -f "$pending" ]; then
      cat >/dev/null
      exit 0
    fi
    input=$(cat)
    info=$(cat "$pending" 2>/dev/null)
    deadline=$(printf '%s' "$info" | sed -n 's/.*"deadline"[[:space:]]*:[[:space:]]*\([0-9][0-9]*\).*/\1/p')
    summary=$(printf '%s' "$info" | sed -n 's/.*"summary"[[:space:]]*:[[:space:]]*"\([^"\\]*\)".*/\1/p')
    [ -n "$deadline" ] || exit 0
    left=$((deadline - $(date +%s)))
    [ "$left" -gt 0 ] || exit 0
    field() {
      printf '%s' "$input" | grep -o "\"$1\"[[:space:]]*:[[:space:]]*\"[A-Za-z0-9_-]*\"" | head -n 1 | sed 's/.*"\([A-Za-z0-9_-]*\)"$/\1/'
    }
    session=$(field session_id)
    event=$(field hook_event_name)
    mkdir -p "$dir/notified" 2>/dev/null
    mkdir "$dir/notified/$deadline-${session:-unknown}" 2>/dev/null || exit 0
    why="${summary:+ ($summary)}"
    note="Stowaway: this Mac goes to sleep in about $left seconds$why. Checkpoint now. Don't start anything long. In a git repo, snapshot uncommitted work without changing any files: git stash store -m 'stowaway checkpoint' \$(git stash create). Write a short note of what's done and what's next, then stop and wait for the user."
    printf '{"systemMessage":"Stowaway: the Mac sleeps in about %s s, so Claude was asked to checkpoint.","hookSpecificOutput":{"hookEventName":"%s","additionalContext":"%s"}}\n' "$left" "${event:-PostToolUse}" "$note"

    """#
}
