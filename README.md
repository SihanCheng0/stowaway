<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="assets/logo/logo-dark.svg">
    <img src="assets/logo/logo-light.svg" width="420" alt="Stowaway">
  </picture>
</p>

<p align="center">Keeps working in your bag.</p>

<p align="center">
  <img src="https://img.shields.io/badge/macOS-13%2B-black" alt="macOS 13+">
  <img src="https://img.shields.io/badge/Swift-5.9-orange" alt="Swift 5.9">
  <img src="https://img.shields.io/badge/license-MIT-blue" alt="MIT license">
</p>

Stowaway is a tiny menu bar app that keeps your MacBook awake with the lid closed. It works on battery, with no external display. Close the laptop, put it in your backpack, and long-running jobs keep going: Claude Code sessions, builds, downloads, test suites.

<p align="center">
  <img src="assets/screenshot-idle.png" width="280" alt="Stowaway sidebar, idle">
  &nbsp;&nbsp;
  <img src="assets/screenshot-active.png" width="280" alt="Stowaway sidebar, keeping the Mac awake">
</p>

## Features

- **One tap.** Click the orb, close the lid, and your Mac stays awake.
- **Auto-off timer.** Choose 30m, 1h, 2h, 4h or no limit. You can extend a running session by 30 minutes.
- **Backpack safeguards.**
  - Normal sleep comes back automatically when the timer ends, when the battery reaches your floor (20% by default), or when macOS reports the Mac is running hot.
  - If the lid is closed when a safeguard trips, the Mac goes to sleep, after a short [checkpoint window](#checkpoint-before-sleep) for your agents.
- **Never stuck awake.**
  - Quitting Stowaway, logging out or shutting down restores normal sleep.
  - After a crash, the next launch restores it.
- **Checkpoint before sleep.** Before a safeguard puts a closed Mac to sleep, Stowaway gives your agents up to a minute to save their work. One click adds a Claude Code hook that tells each session.
- **Glanceable.**
  - The menu bar icon shows a moon (🌙) when idle. While Stowaway is keeping the Mac awake, it shows a cup (☕) and the time left.
  - Left-click the icon to open the sidebar. Right-click it to toggle directly.

> **Heat:** a closed laptop in a bag can get warm. Leave **Stop if Mac runs hot** on. It ends the session as soon as macOS reports a serious thermal state.

## Checkpoint before sleep

When a safeguard is about to put a closed Mac to sleep, Stowaway first keeps it awake a little longer so your agents can save their work:

- **60 seconds** when the timer ends or the battery reaches your floor
- **20 seconds** if the Mac is hot
- **no wait** if it's critically hot

During that window Stowaway:
- writes `~/.config/stowaway/sleep-pending.json` (reason, deadline and battery), and deletes it when the window ends.
- runs `~/.config/stowaway/before-sleep`, if you've created that script and made it executable.

The menu bar shows the countdown. If you open the lid, the window ends and the Mac doesn't sleep. If you plug in the charger or extend the timer, the session keeps going. It's on by default. Switch it off under **Safeguards**.

### Claude Code

Click **Add to Claude Code** under the toggle. Stowaway adds a hook to `~/.claude/settings.json` and keeps your old file as `settings.json.stowaway-backup`.

- **What the hook does:** after each tool call, it checks whether sleep is coming. If it is, it tells that session once to finish up, snapshot uncommitted work, write a short note of what's done and what's next, and stop. The rest of the time it prints nothing.
- **Long commands:** an agent in the middle of one hears about it when the command finishes.
- **Settings:** if `settings.json` isn't valid JSON, Stowaway leaves it alone and copies the hook to your clipboard instead. If you use `CLAUDE_CONFIG_DIR`, paste the hook into that folder's `settings.json`.

### Your own script

`before-sleep` runs as you, in a login shell. It gets these environment variables:

| Variable | Value |
|-|-|
| `STOWAWAY_REASON` | `timer`, `battery` or `heat` |
| `STOWAWAY_SUMMARY` | a readable reason, such as `battery at 19%` |
| `STOWAWAY_DEADLINE` | when the Mac sleeps (Unix time) |
| `STOWAWAY_SECONDS` | seconds until then |
| `STOWAWAY_LID` | `closed` or `open` |
| `STOWAWAY_BATTERY` | battery percentage |

Stowaway stops the script at the deadline. Its output goes to `~/Library/Logs/Stowaway/before-sleep.log`. This example snapshots uncommitted changes in every repo under `~/Projects`, without touching your files:

```sh
#!/bin/sh
# ~/.config/stowaway/before-sleep
for repo in "$HOME"/Projects/*/; do
  cd "$repo" && git rev-parse --is-inside-work-tree >/dev/null 2>&1 || continue
  stash=$(git stash create) && [ -n "$stash" ] &&
    git stash store -m "stowaway: $STOWAWAY_SUMMARY" "$stash"
done
```

Make it executable with `chmod +x ~/.config/stowaway/before-sleep`. To get a snapshot back, use `git stash list` and `git stash apply`.

## Install

With [Homebrew](https://brew.sh):

```bash
brew install --cask SihanCheng0/tap/stowaway
```

Or download `Stowaway-<version>.dmg` from [Releases](https://github.com/SihanCheng0/stowaway/releases) and drag Stowaway to Applications.

> **First launch from the DMG:** releases aren't notarized by Apple yet, so macOS blocks the first launch. Open Stowaway once. Then go to **System Settings → Privacy & Security** and click **Open Anyway**. You do this once for each version you download. Homebrew installs skip this step.

Requires macOS 13 Ventura or later.

## How it works

macOS always sleeps when the lid closes, unless an external display is attached. Apps can't override that with the usual keep-awake APIs (`caffeinate` and power assertions). The one supported switch is `pmset -a disablesleep 1`, and it needs root.

| What | How |
|-|-|
| Keep awake with the lid closed | `pmset -a disablesleep 1` (and `0` to restore) |
| Read the current state | the `SleepDisabled` line of `pmset -g` |
| Battery | IOKit `IOPSCopyPowerSourcesInfo` |
| Lid open or closed | IORegistry `IOPMrootDomain` → `AppleClamshellState` |
| Heat | `ProcessInfo.thermalState` (stops at *serious*) |
| Sleep right away after an auto-stop | `pmset sleepnow` (no root needed) |
| Warn agents first | `~/.config/stowaway/sleep-pending.json`, read by a Claude Code `PostToolUse` hook |

This is also why Stowaway isn't on the Mac App Store. Sandboxed apps can't run anything as root.

## Security

The first time you use Stowaway, it asks for your administrator password **once**. That installs a single rule at `/etc/sudoers.d/stowaway`:

```
<you> ALL=(root) NOPASSWD: /usr/bin/pmset -a disablesleep 0, /usr/bin/pmset -a disablesleep 1
```

- **What it allows:** only those two exact commands, only for your user. Nothing else gets passwordless root.
- **How it's installed:** the rule is checked with `visudo` before it's put in place.
- **Why it's needed:** Stowaway won't start a session without it. Without the rule, Stowaway couldn't turn sleep back on by itself while your Mac is in a bag.
- **Removing it:** click **Remove authorization** in the sidebar, or run:

```bash
sudo rm /etc/sudoers.d/stowaway
```

The code that writes the rule is in [`SudoersHelper.swift`](Stowaway/Services/SudoersHelper.swift).

## Privacy

Stowaway collects nothing. Its only network request is a daily check of `api.github.com` for a newer release. The request carries the app's version in its User-Agent header, and the check never downloads anything. If you installed with Homebrew, the update button copies `brew upgrade --cask stowaway` for you.

## Uninstall

- **Homebrew:**
  ```bash
  brew uninstall --zap --cask stowaway
  ```
  `--zap` also removes the sudoers rule, Stowaway's preferences and `~/.config/stowaway`.
- **Manual install:** click **Remove authorization**, quit Stowaway, then move it to the Trash.
- **Claude Code hook:** remove Stowaway's entry from `hooks.PostToolUse` in `~/.claude/settings.json`. A leftover entry is harmless: it does nothing once `~/.config/stowaway` is gone.

## Build from source

```bash
brew install xcodegen
xcodegen generate
xcodebuild -project Stowaway.xcodeproj -scheme Stowaway -configuration Release build
```

To run the tests:

```bash
xcodebuild test -project Stowaway.xcodeproj -scheme Stowaway
```

To also render sidebar snapshots to PNGs, prefix the test command with `TEST_RUNNER_STOWAWAY_SNAPSHOT_DIR=/some/dir`. For a quick unsigned local DMG, run `./build-dmg.sh`.

## Releasing

Releases are ad-hoc signed and not notarized for now.

**Each release:**
1. Bump `MARKETING_VERSION` in `project.yml` and run `xcodegen generate`. Commit `project.yml` and `Stowaway.xcodeproj`, then push.
2. Build the DMG. This also updates the cask's `version` and `sha256` in your `homebrew-tap` checkout (`TAP_DIR`, default `~/Projects/homebrew-tap`).
   ```bash
   scripts/release.sh --unsigned
   ```
3. Publish. This creates a draft GitHub release, pushes the cask, then publishes the release. The release notes include install instructions.
   ```bash
   scripts/publish.sh
   ```

The styled DMG comes from the script set in `DMG_BUILDER`. Set `DMG_BUILDER=none` for a plain `hdiutil` DMG.

**Optional: a stable signature without a developer account.** An ad-hoc signature is different for every build, so `brew upgrade` warns that Stowaway's signer changed. To avoid that, create a self-signed certificate once in Keychain Access → Certificate Assistant → Create a Certificate, with Certificate Type **Code Signing**. Open the certificate and set **Code Signing** to **Always Trust**. Then release with:

```bash
ADHOC_IDENTITY="<certificate name>" scripts/release.sh --unsigned
```

The first upgrade from an ad-hoc release may still show Homebrew's signer-changed warning once.

**Switching to notarized releases** (needs the paid [Apple Developer Program](https://developer.apple.com/programs/)):
1. Create a **Developer ID Application** certificate: Xcode → Settings → Accounts → Manage Certificates → +.
2. Store notarization credentials. You'll need an app-specific password from [account.apple.com](https://account.apple.com).
   ```bash
   xcrun notarytool store-credentials stowaway-notary --apple-id <you@example.com> --team-id <TEAM_ID>
   ```
3. Release without `--unsigned`. The script signs, notarizes and staples the DMG.
   ```bash
   TEAM_ID=<TEAM_ID> scripts/release.sh
   ```
4. Remove the quarantine `postflight_steps` from the cask, and the first-launch note from this README.

## License

[MIT](LICENSE)
