import SwiftUI

struct SidebarView: View {
    @ObservedObject var controller: AwakeController
    @ObservedObject var presentation: SidebarPresentation
    @ObservedObject var updates: UpdateChecker
    @State private var launchAtLogin = LoginItem.isEnabled
    @State private var copiedUpgradeCommand = false
    @State private var claudeHookInstalled = ClaudeHookInstaller().isInstalled
    @State private var addedClaudeHook = false

    var body: some View {
        // Small screens (or the extra setup card) get a tighter layout instead of clipping.
        ViewThatFits(in: .vertical) {
            content(compact: false)
            content(compact: true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: controller.isActive)
        .animation(.easeInOut(duration: 0.2), value: controller.isAuthorized)
        .animation(.easeInOut(duration: 0.2), value: updates.available)
        .onChange(of: presentation.isVisible) { visible in
            // Pick up a hook added or removed by hand since the sidebar was last open.
            if visible, !addedClaudeHook { claudeHookInstalled = ClaudeHookInstaller().isInstalled }
        }
    }

    private func content(compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            if !controller.isAuthorized {
                SetupCard { controller.authorize() }
                    .padding(.top, compact ? 12 : 16)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            Spacer(minLength: compact ? 14 : 24)
            hero(compact: compact)
            Spacer(minLength: compact ? 14 : 24)

            statusSection
            safeguardsSection
                .padding(.top, compact ? 14 : 20)
            footer
                .padding(.top, compact ? 12 : 16)
        }
        .padding(20)
    }

    // MARK: - Sections

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Stowaway")
                    .font(.system(size: 15, weight: .semibold))
                Text(controller.isActive ? "Your Mac stays awake" : "Keeps working in your bag")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let release = updates.available {
                updateButton(release)
            }
            Button(action: presentation.close) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(Color.primary.opacity(0.06)))
            }
            .buttonStyle(.plain)
            .help("Close (Esc)")
        }
    }

    private func hero(compact: Bool) -> some View {
        VStack(spacing: compact ? 14 : 20) {
            PowerOrb(
                isActive: controller.isActive,
                animates: presentation.isVisible,
                size: compact ? 112 : 148,
                action: controller.toggle
            )

            VStack(spacing: 6) {
                Text(heroLabel)
                    .textCase(.uppercase)
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(1.4)
                    .foregroundStyle(controller.isActive ? Color.ember : Color.secondary)
                heroDetail
            }
            .frame(height: compact ? 70 : 76)

            DurationChips(selected: controller.duration, onSelect: controller.select)
        }
        .frame(maxWidth: .infinity)
    }

    private var heroLabel: String {
        if controller.pendingSleep != nil { return "Sleeping soon" }
        return controller.isActive ? "Awake · lid can close" : "Sleeps normally"
    }

    @ViewBuilder
    private var heroDetail: some View {
        if let pending = controller.pendingSleep, let countdown = controller.sleepCountdown {
            Text(Countdown.clock(countdown))
                .font(.system(size: 34, weight: .light, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText(countsDown: true))
            Text("\(pending.reason.summary.capitalizedFirst) · checkpointing")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        } else if controller.isActive, let remaining = controller.remaining, let endDate = controller.endDate {
            Text(Countdown.clock(remaining))
                .font(.system(size: 34, weight: .light, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText(countsDown: true))
            HStack(spacing: 8) {
                Text("until \(endDate.formatted(date: .omitted, time: .shortened))")
                Button("+30m") { controller.extend() }
                    .buttonStyle(ChipButtonStyle(compact: true))
            }
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
        } else if controller.isActive {
            Text(controller.isExternal ? "Set outside Stowaway" : "No time limit")
                .font(.system(size: 22, weight: .light, design: .rounded))
            Text("Battery and heat safeguards still apply")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        } else {
            Text("Tap to stay awake")
                .font(.system(size: 22, weight: .light, design: .rounded))
            Text("Close the lid. Your agents keep working.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }

    private var statusSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel("Status")
                .padding(.bottom, 6)
            StatRow(symbol: batterySymbol, title: "Battery", value: batteryText)
            StatRow(symbol: "laptopcomputer", title: "Lid", value: controller.system.lidClosed ? "Closed" : "Open")
            StatRow(
                symbol: "thermometer.medium",
                title: "Temperature",
                value: controller.system.thermal.label,
                tint: controller.system.thermal.tint
            )
            // While it's missing, the setup card above says so.
            if controller.isAuthorized {
                StatRow(symbol: "lock.shield", title: "Authorization", value: "Ready")
            }
        }
    }

    private var safeguardsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel("Safeguards")
                .padding(.bottom, 6)
            HStack(spacing: 10) {
                RowIcon(symbol: "battery.25")
                Text("Stop at battery")
                    .font(.system(size: 12))
                Spacer()
                MiniStepper(value: $controller.batteryFloor, range: SafetySettings.batteryFloorRange, step: 5) { "\($0)%" }
            }
            .padding(.vertical, 4)
            SettingToggle(symbol: "thermometer.high", title: "Stop if Mac runs hot", isOn: $controller.thermalGuard)
            SettingToggle(symbol: "square.and.arrow.down", title: "Checkpoint before sleep", isOn: $controller.checkpointBeforeSleep)
                .help("Before a safeguard puts a closed Mac to sleep, Stowaway waits up to a minute so agents can save their work")
            if showsClaudeHookButton {
                claudeHookButton
                    .transition(.opacity)
            }
            SettingToggle(symbol: "sunrise", title: "Launch at login", isOn: Binding(
                get: { launchAtLogin },
                set: { enabled in
                    LoginItem.set(enabled)
                    launchAtLogin = LoginItem.isEnabled
                }
            ))
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let notice = controller.notice {
                Label(notice, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(Color.ember)
            } else if let lastEnd = controller.lastEnd {
                Label(
                    "Last session ended \(lastEnd.date.formatted(date: .omitted, time: .shortened)) · \(lastEnd.reason.summary)",
                    systemImage: "clock.arrow.circlepath"
                )
                .foregroundStyle(.secondary)
            }

            Divider().opacity(0.6)

            HStack {
                if controller.isAuthorized {
                    Button("Remove authorization") { controller.removeAuthorization() }
                        .help("Deletes the sudo rule Stowaway installed")
                }
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .font(.system(size: 11))
    }

    /// One setup step at a time: offered after authorization, until the hook is installed.
    private var showsClaudeHookButton: Bool {
        guard controller.isAuthorized, controller.checkpointBeforeSleep else { return false }
        return addedClaudeHook || (!claudeHookInstalled && ClaudeHookInstaller().isClaudeCodePresent)
    }

    /// Confirms briefly after installing, then goes away.
    private var claudeHookButton: some View {
        Button(action: addClaudeHook) {
            Label(
                addedClaudeHook ? "Added to Claude Code" : "Add to Claude Code",
                systemImage: addedClaudeHook ? "checkmark" : "plus.circle"
            )
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(addedClaudeHook ? Color.secondary : Color.ember)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(addedClaudeHook)
        .padding(.leading, 28)
        .padding(.bottom, 4)
        .help("Adds a hook to ~/.claude/settings.json that asks Claude Code sessions to checkpoint before the Mac sleeps")
    }

    private func addClaudeHook() {
        do {
            try ClaudeHookInstaller().install()
            claudeHookInstalled = true
            addedClaudeHook = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                withAnimation(.easeInOut(duration: 0.2)) { addedClaudeHook = false }
            }
        } catch ClaudeHookInstaller.InstallError.unreadableSettings(let snippet) {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(snippet, forType: .string)
            controller.notice = ClaudeHookInstaller.InstallError.unreadableSettings(snippet: snippet).localizedDescription
        } catch {
            controller.notice = "Couldn't add the Claude Code hook: \(error.localizedDescription)"
        }
    }

    /// Lives in the header so it never adds height to a tight layout.
    private func updateButton(_ release: ReleaseInfo) -> some View {
        Button {
            if updates.isHomebrewInstall {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(UpdateChecker.brewUpgradeCommand, forType: .string)
                copiedUpgradeCommand = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) { copiedUpgradeCommand = false }
            } else {
                NSWorkspace.shared.open(release.url)
                presentation.close()
            }
        } label: {
            Label(
                copiedUpgradeCommand ? "Copied" : "v\(release.version)",
                systemImage: copiedUpgradeCommand ? "checkmark" : "arrow.up.circle.fill"
            )
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(Capsule().fill(Color.ember))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(updates.isHomebrewInstall
            ? "Stowaway \(release.version) is available. Click to copy: \(UpdateChecker.brewUpgradeCommand)"
            : "Stowaway \(release.version) is available. Click to open the release page.")
        .accessibilityLabel("Update to Stowaway \(release.version)")
    }

    // MARK: - Formatting

    private var batteryText: String {
        let battery = controller.system.battery
        guard let percent = battery.percent else { return "Power adapter" }
        if battery.charging { return "\(percent)% · charging" }
        return battery.onBattery ? "\(percent)%" : "\(percent)% · plugged in"
    }

    private var batterySymbol: String {
        let battery = controller.system.battery
        guard let percent = battery.percent else { return "powerplug" }
        if battery.charging { return "battery.100.bolt" }
        switch percent {
        case 88...: return "battery.100"
        case 63..<88: return "battery.75"
        case 38..<63: return "battery.50"
        case 13..<38: return "battery.25"
        default: return "battery.0"
        }
    }
}

private extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}

private extension ProcessInfo.ThermalState {
    var label: String {
        switch self {
        case .nominal: return "Normal"
        case .fair: return "Warm"
        case .serious: return "Hot"
        case .critical: return "Critical"
        @unknown default: return "Unknown"
        }
    }

    var tint: Color {
        switch self {
        case .nominal: return .secondary
        case .fair: return .yellow
        case .serious: return .orange
        case .critical: return .red
        @unknown default: return .secondary
        }
    }
}
