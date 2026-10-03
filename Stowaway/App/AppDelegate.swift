import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: AwakeController?
    private var sidebar: SidebarController?
    private var statusItem: StatusItemController?
    private var updates: UpdateChecker?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Unit tests run inside the app; keep them away from the real power settings.
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }

        let controller = AwakeController(power: PowerManager(), monitor: SystemMonitor(), authorizer: SudoersHelper())
        controller.start()
        let updates = UpdateChecker()
        updates.start()
        let sidebar = SidebarController(controller: controller, updates: updates)
        statusItem = StatusItemController(controller: controller, sidebar: sidebar)
        self.controller = controller
        self.sidebar = sidebar
        self.updates = updates

        if !controller.isAuthorized {
            sidebar.show(from: nil)
        }
    }

    /// Also runs on logout, restart and shutdown.
    func applicationWillTerminate(_ notification: Notification) {
        controller?.restoreForQuit()
    }
}
