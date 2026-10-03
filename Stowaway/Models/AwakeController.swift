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

    var remaining: TimeInterval? {
        endDate.map { max(0, $0.timeIntervalSince(now)) }
    }

    var settings: SafetySettings {
        SafetySettings(batteryFloor: batteryFloor, thermalGuard: thermalGuard)
    }

    private enum Keys {
        static let duration = "duration"
        static let batteryFloor = "batteryFloor"
        static let thermalGuard = "thermalGuard"
        static let sessionActive = "sessionActive"
    }

    private static let systemRefreshInterval: TimeInterval = 5
    private static let autoStopRetryDelay: TimeInterval = 30

    private let power: PowerControlling
    private let monitor: SystemMonitoring
    private let authorizer: Authorizing
    private let defaults: UserDefaults
    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []
    private var lastSystemRefresh = Date.distantPast
    private var autoStopRetryAfter: Date?

    init(power: PowerControlling, monitor: SystemMonitoring, authorizer: Authorizing, defaults: UserDefaults = .standard) {
        self.power = power
        self.monitor = monitor
        self.authorizer = authorizer
        self.defaults = defaults
        system = monitor.snapshot()
        duration = AwakeDuration(rawValue: defaults.object(forKey: Keys.duration) as? Int ?? -1) ?? .twoHours
        let floor = defaults.object(forKey: Keys.batteryFloor) as? Int ?? 20
        batteryFloor = min(max(floor, SafetySettings.batteryFloorRange.lowerBound), SafetySettings.batteryFloorRange.upperBound)
        thermalGuard = defaults.object(forKey: Keys.thermalGuard) as? Bool ?? true
    }

    /// Call once at launch.
    func start() {
        syncOnLaunch()
        startTicking()
    }

    func syncOnLaunch() {
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
        }
    }

    func extend(by interval: TimeInterval = 30 * 60) {
        guard isActive, let endDate else { return }
        self.endDate = max(endDate, now).addingTimeInterval(interval)
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
        isActive = false
        isExternal = false
        endDate = nil
        autoStopRetryAfter = nil
        lastEnd = SessionEnd(reason: reason, date: Date())
        defaults.set(false, forKey: Keys.sessionActive)
        if reason.isAutomatic, system.lidClosed, !system.externalDisplay {
            power.sleepNow()
        }
        return true
    }

    /// On quit or logout, only undo what Stowaway itself turned on.
    func restoreForQuit() {
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
        guard isActive,
              let reason = SafetyPolicy.evaluate(now: now, endDate: endDate, system: system, settings: settings)
        else { return }
        if let retryAfter = autoStopRetryAfter, now < retryAfter { return }
        if !end(reason) {
            autoStopRetryAfter = now.addingTimeInterval(Self.autoStopRetryDelay)
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
