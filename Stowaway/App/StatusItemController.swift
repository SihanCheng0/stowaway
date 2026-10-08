import AppKit
import Combine

/// Menu bar icon. Left-click opens the sidebar, right-click (or control-click) toggles awake mode.
@MainActor
final class StatusItemController: NSObject {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let controller: AwakeController
    private let sidebar: SidebarController
    private var renderedSymbol: String?
    private var cancellables = Set<AnyCancellable>()

    init(controller: AwakeController, sidebar: SidebarController) {
        self.controller = controller
        self.sidebar = sidebar
        super.init()

        guard let button = statusItem.button else { return }
        button.target = self
        button.action = #selector(handleClick(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.imagePosition = .imageLeading
        button.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        button.toolTip = "Stowaway: click to open, right-click to toggle"

        controller.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.render() }
            .store(in: &cancellables)
        render()
    }

    @objc private func handleClick(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
            controller.toggle()
        } else {
            sidebar.toggle(from: sender)
        }
    }

    private func render() {
        guard let button = statusItem.button else { return }

        let checkpointing = controller.sleepCountdown != nil
        let symbol = checkpointing ? "hourglass" : controller.isActive ? "cup.and.saucer.fill" : "moon.zzz"
        if symbol != renderedSymbol {
            let description = checkpointing ? "Stowaway: sleeping soon"
                : controller.isActive ? "Stowaway: staying awake" : "Stowaway: normal sleep"
            let image = NSImage(systemSymbolName: symbol, accessibilityDescription: description)?
                .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 13, weight: .regular))
            image?.isTemplate = true
            button.image = image
            renderedSymbol = symbol
        }

        let title: String
        if let countdown = controller.sleepCountdown {
            title = " " + Countdown.clock(countdown)
        } else if controller.isActive {
            title = controller.remaining.map { " " + Countdown.compact($0) } ?? ""
        } else {
            title = ""
        }
        if button.title != title {
            button.title = title
        }
    }
}
