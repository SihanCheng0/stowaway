import AppKit
import Combine

@MainActor
final class AwakeController: ObservableObject {
    struct SessionEnd: Equatable {
        let reason: EndReason
        let date: Date
    }

    @Published private(set) var isActive = false
    /// Sleep was disabled by something other than Stowaway, e.g. `pmset` in a terminal.
    @Published private(set) var isExternal = false
    @Published private(set) var endDate: Date?
    @Published private(set) var isAuthorized = false
    @Published private(set) var system: SystemSnapshot
    @Published private(set) var lastEnd: SessionEnd?
    @Published private(set) var now = Date()
    /// A safeguard has tripped and the Mac stays awake until the deadline so agents can checkpoint.
    @Published private(set) var pendingSleep: PendingSleep?
    @Published var notice: String?

    @Published var duration: AwakeDuration {
        didSet { defaults.set(duration.rawValue, forKey: Keys.duration) }
    }
    @Published var batteryFloor: Int {
        didSet { defaults.set(batteryFloor, forKey: Keys.batteryFloor) }
    }
    @Published var thermalGuard: Bool {
        didSet { defaults.set(thermalGuard, forKey: Keys.thermalGuard) }
    }
    @Published var checkpointBeforeSleep: Bool {
        didSet { defaults.set(checkpointBeforeSleep, forKey: Keys.checkpointBeforeSleep) }
    }

    var remaining: TimeInterval? {
        endDate.map { max(0, $0.timeIntervalSince(now)) }
    }

    /// Seconds until a pending checkpoint window ends and the Mac sleeps.
    var sleepCountdown: TimeInterval? {
        pendingSleep.map { max(0, $0.deadline.timeIntervalSince(now)) }
    }

    var settings: SafetySettings {
        SafetySettings(batteryFloor: batteryFloor, thermalGuard: thermalGuard)
    }

    private enum Keys {
        static let duration = "duration"
        static let batteryFloor = "batteryFloor"
        static let thermalGuard = "thermalGuard"
        static let checkpointBeforeSleep = "checkpointBeforeSleep"
        static let sessionActive = "sessionActive"
    }

    private static let systemRefreshInterval: TimeInterval = 5
    private static let autoStopRetryDelay: TimeInterval = 30

    private let power: PowerControlling
    private let monitor: SystemMonitoring
    private let authorizer: Authorizing
    private let checkpoint: CheckpointHooking
    private let defaults: UserDefaults
    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []
    private var lastSystemRefresh = Date.distantPast
    private var autoStopRetryAfter: Date?

    init(
        power: PowerControlling,
        monitor: SystemMonitoring,
        authorizer: Authorizing,
        checkpoint: CheckpointHooking,
        defaults: UserDefaults = .standard
    ) {
        self.power = power
        self.monitor = monitor
        self.authorizer = authorizer
        self.checkpoint = checkpoint
        self.defaults = defaults
        system = monitor.snapshot()
        duration = AwakeDuration(rawValue: defaults.object(forKey: Keys.duration) as? Int ?? -1) ?? .twoHours
        let floor = defaults.object(forKey: Keys.batteryFloor) as? Int ?? 20
        batteryFloor = min(max(floor, SafetySettings.batteryFloorRange.lowerBound), SafetySettings.batteryFloorRange.upperBound)
        thermalGuard = defaults.object(forKey: Keys.thermalGuard) as? Bool ?? true
        checkpointBeforeSleep = defaults.object(forKey: Keys.checkpointBeforeSleep) as? Bool ?? true
    }

    /// Call once at launch.
    func start() {
        syncOnLaunch()
        startTicking()
    }

    func syncOnLaunch() {
        // A window left over from a crash or a forced sleep is stale.
        checkpoint.finish()
        isAuthorized = authorizer.isInstalled()
        guard power.isSleepDisabled() else {
            defaults.set(false, forKey: Keys.sessionActive)
            return
        }
        isActive = true
        if defaults.bool(forKey: Keys.sessionActive) {
            // Stowaway disabled sleep and never got to restore it (crash or force quit).
            end(.recovered)
        } else {
            isExternal = true
        }
    }

    // MARK: - Actions

    func toggle() {
        if isActive {
            end(.manual)
        } else {
            enable()
        }
    }

    func enable() {
        guard !isActive else { return }
        // Without the rule Stowaway couldn't switch sleep back on by itself from inside a bag.
        guard isAuthorized || authorize() else { return }
        refreshSystem()
        if let blocker = SafetyPolicy.evaluate(now: Date(), endDate: nil, system: system, settings: settings) {
            notice = "Not started: \(blocker.summary)."
            return
        }
        do {
            try power.setSleepDisabled(true, allowPrompt: true)
        } catch {
            report(error)
            return
        }
        isActive = true
        notice = nil
        startCountdown(duration)
    }

    /// Picks a duration. Restarts the countdown if a session is running.
    func select(_ newDuration: AwakeDuration) {
        duration = newDuration
        if isActive {
            startCountdown(newDuration)
            cancelTimerCheckpoint()
        }
    }

    func extend(by interval: TimeInterval = 30 * 60) {
        guard isActive, let endDate else { return }
        self.endDate = max(endDate, now).addingTimeInterval(interval)
        cancelTimerCheckpoint()
    }

    /// Restores normal sleep. Returns false if macOS refused.
    @discardableResult
    func end(_ reason: EndReason) -> Bool {
        do {
            try power.setSleepDisabled(false, allowPrompt: !reason.isAutomatic)
        } catch {
            report(error)
            return false
        }
        if pendingSleep != nil {
            checkpoint.finish()
            pendingSleep = nil
        }
        isActive = false
        isExternal = false
        endDate = nil
        autoStopRetryAfter = nil
        lastEnd = SessionEnd(reason: reason, date: Date())
        defaults.set(false, forKey: Keys.sessionActive)
        if reason.isAutomatic {
            // The snapshot can be seconds old: don't sleep a Mac someone just opened.
            refreshSystem()
            if system.wouldSleep { power.sleepNow() }
        }
        return true
    }

    /// On quit or logout, only undo what Stowaway itself turned on.
    func restoreForQuit() {
        checkpoint.finish()
        guard isActive, !isExternal else { return }
        end(.quit)
    }

    @discardableResult
    func authorize() -> Bool {
        do {
            try authorizer.install()
            isAuthorized = true
            notice = nil
        } catch {
            report(error)
        }
        return isAuthorized
    }

    func removeAuthorization() {
        if isActive, !end(.manual) { return }
        do {
            try authorizer.uninstall()
        } catch {
            report(error)
        }
        isAuthorized = authorizer.isInstalled()
    }

    // MARK: - Monitoring

    func refreshSystem() {
        system = monitor.snapshot()
        lastSystemRefresh = Date()
    }

    func tick(at date: Date = Date()) {
        now = date
        if date.timeIntervalSince(lastSystemRefresh) >= Self.systemRefreshInterval {
            refreshSystem()
        }
        checkSafeguards()
    }

    /// Re-reads the real power state, e.g. after the Mac wakes.
    func resync() {
        refreshSystem()
        let actuallyDisabled = power.isSleepDisabled()
        if actuallyDisabled != isActive {
            if pendingSleep != nil {
                checkpoint.finish()
                pendingSleep = nil
            }
            isActive = actuallyDisabled
            isExternal = actuallyDisabled
            endDate = nil
            defaults.set(false, forKey: Keys.sessionActive)
        }
        tick()
    }

    // MARK: - Private

    private func startCountdown(_ duration: AwakeDuration) {
        now = Date()
        endDate = duration.interval.map { now.addingTimeInterval($0) }
        isExternal = false
        defaults.set(true, forKey: Keys.sessionActive)
    }

    private func checkSafeguards() {
        guard isActive else { return }
        if let pending = pendingSleep {
            advanceCheckpoint(pending)
            return
        }
        guard let reason = SafetyPolicy.evaluate(now: now, endDate: endDate, system: system, settings: settings),
              autoStopRetryAfter.map({ now >= $0 }) ?? true
        else { return }
        let grace = checkpointBeforeSleep ? CheckpointPolicy.grace(for: reason, system: system) : 0
        guard grace > 0 else {
            stop(for: reason)
            return
        }
        let pending = PendingSleep(reason: reason, deadline: now.addingTimeInterval(grace))
        pendingSleep = pending
        checkpoint.begin(pending, system: system)
    }

    /// A window only shrinks, by the rule that opened it: hotter means sooner, and critical heat,
    /// an opened lid or switching the setting off mean now. It stays open until sleep is actually
    /// restored, so a failed stop is retried rather than forgotten. A cooler Mac doesn't cancel it
    /// (told to stop, the agents ease the load), but plugging in the charger does.
    private func advanceCheckpoint(_ pending: PendingSleep) {
        if case .lowBattery = pending.reason, !system.battery.onBattery {
            cancelCheckpoint()
            return
        }
        let grace = checkpointBeforeSleep ? CheckpointPolicy.grace(for: pending.reason, system: system) : 0
        let deadline = min(pending.deadline, now.addingTimeInterval(grace))
        guard now >= deadline else {
            if deadline < pending.deadline {
                let sooner = PendingSleep(reason: pending.reason, deadline: deadline)
                pendingSleep = sooner
                checkpoint.begin(sooner, system: system)
            }
            return
        }
        guard autoStopRetryAfter.map({ now >= $0 }) ?? true else { return }
        if !end(pending.reason) {
            // The window is over even though sleep couldn't be restored yet. Try again shortly.
            checkpoint.finish()
            autoStopRetryAfter = now.addingTimeInterval(Self.autoStopRetryDelay)
        }
    }

    private func stop(for reason: EndReason) {
        if !end(reason) {
            autoStopRetryAfter = now.addingTimeInterval(Self.autoStopRetryDelay)
        }
    }

    private func cancelCheckpoint() {
        checkpoint.finish()
        pendingSleep = nil
    }

    /// More time on the clock: a window opened because the timer ran out no longer applies.
    private func cancelTimerCheckpoint() {
        if pendingSleep?.reason == .timerFinished {
            cancelCheckpoint()
        }
    }

    private func report(_ error: Error) {
        if error as? StowawayError == .cancelled { return }
        notice = error.localizedDescription
    }

    private func startTicking() {
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        timer.tolerance = 0.2
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer

        observe(NotificationCenter.default, ProcessInfo.thermalStateDidChangeNotification) { $0.refreshSystem(); $0.tick() }
        observe(NSWorkspace.shared.notificationCenter, NSWorkspace.didWakeNotification) { $0.resync() }
    }

    private func observe(_ center: NotificationCenter, _ name: Notification.Name, _ handler: @escaping (AwakeController) -> Void) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                handler(self)
            }
        }
        observers.append(token)
    }
}
