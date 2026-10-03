import SwiftUI
import XCTest
@testable import Stowaway

/// Renders the sidebar to PNGs for visual review. Set `STOWAWAY_SNAPSHOT_DIR` to run
/// (via xcodebuild: `TEST_RUNNER_STOWAWAY_SNAPSHOT_DIR=/some/dir xcodebuild test ...`).
@MainActor
final class SidebarSnapshotTests: XCTestCase {
    func testRenderSidebarStates() async throws {
        guard let directory = ProcessInfo.processInfo.environment["STOWAWAY_SNAPSHOT_DIR"] else {
            throw XCTSkip("Set STOWAWAY_SNAPSHOT_DIR to render snapshots")
        }
        let states: [(name: String, authorized: Bool, active: Bool, update: Bool)] = [
            ("setup", false, false, false),
            ("idle", true, false, false),
            ("active", true, true, false),
            ("update", true, false, true),
        ]
        // 760pt is roughly a 13" MacBook Air's visible height minus the sidebar margins.
        for state in states {
            for (scheme, height) in [(ColorScheme.light, 760.0), (.dark, 900.0)] {
                let controller = AwakeController(
                    power: MockPower(),
                    monitor: MockMonitor(),
                    authorizer: MockAuthorizer(installed: state.authorized),
                    defaults: makeTestDefaults()
                )
                controller.syncOnLaunch()
                if state.active {
                    controller.enable()
                    controller.tick(at: Date().addingTimeInterval(1273))
                }
                if state.update {
                    // Stacks the update link under a "Last session ended" line.
                    controller.enable()
                    controller.toggle()
                }
                let presentation = SidebarPresentation()
                presentation.isVisible = true
                let updates = UpdateChecker(
                    fetcher: MockReleaseFetcher(version: state.update ? "1.1.0" : "1.0.0"),
                    currentVersion: "1.0.0",
                    isHomebrewInstall: false
                )
                await updates.check()

                let view = SidebarView(controller: controller, presentation: presentation, updates: updates)
                    .frame(width: 300, height: height)
                    .background(scheme == .dark ? Color(white: 0.16) : Color(white: 0.94))
                    .environment(\.colorScheme, scheme)
                let renderer = ImageRenderer(content: view)
                renderer.scale = 2
                let image = try XCTUnwrap(renderer.cgImage)
                let png = try XCTUnwrap(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
                let file = URL(fileURLWithPath: directory)
                    .appendingPathComponent("sidebar-\(state.name)-\(scheme == .dark ? "dark" : "light").png")
                try png.write(to: file)
            }
        }
    }
}
