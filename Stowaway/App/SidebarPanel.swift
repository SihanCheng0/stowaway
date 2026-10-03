import AppKit
import SwiftUI

/// Borderless panel that takes key status (for Esc) without activating Stowaway.
final class SidebarPanel: NSPanel {
    var onCancel: (() -> Void)?

    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        isFloatingPanel = true
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        isMovable = false
        hidesOnDeactivate = false
        animationBehavior = .none
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }
}

@MainActor
final class SidebarPresentation: ObservableObject {
    @Published var isVisible = false
    var close: () -> Void = {}
}

/// Slides the sidebar in from the right edge of the screen holding the menu bar icon.
@MainActor
final class SidebarController {
    private static let width: CGFloat = 300
    private static let margin: CGFloat = 8
    private static let cornerRadius: CGFloat = 20
    private static let slideDistance: CGFloat = 28

    private let presentation = SidebarPresentation()
    private let panel = SidebarPanel()
    private var screen: NSScreen?
    private var clickMonitor: Any?
    private var screenObserver: NSObjectProtocol?

    init(controller: AwakeController, updates: UpdateChecker) {
        let background = NSVisualEffectView()
        background.material = .sidebar
        background.blendingMode = .behindWindow
        background.state = .active
        background.maskImage = Self.roundedMask(radius: Self.cornerRadius)

        let hosting = NSHostingView(rootView: SidebarView(controller: controller, presentation: presentation, updates: updates))
        // The panel's frame is fixed to the screen height; don't let SwiftUI resize it to fit content.
        hosting.sizingOptions = []
        hosting.translatesAutoresizingMaskIntoConstraints = false
        background.addSubview(hosting)
        NSLayoutConstraint.activate([
            hosting.leadingAnchor.constraint(equalTo: background.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: background.trailingAnchor),
            hosting.topAnchor.constraint(equalTo: background.topAnchor),
            hosting.bottomAnchor.constraint(equalTo: background.bottomAnchor),
        ])
        panel.contentView = background
        panel.onCancel = { [weak self] in self?.hide() }
        presentation.close = { [weak self] in self?.hide() }
    }

    func toggle(from button: NSStatusBarButton?) {
        if presentation.isVisible {
            hide()
        } else {
            show(from: button)
        }
    }

    func show(from button: NSStatusBarButton?) {
        guard let screen = button?.window?.screen ?? NSScreen.main ?? NSScreen.screens.first else { return }
        self.screen = screen
        let target = Self.frame(on: screen)
        panel.setFrame(target.offsetBy(dx: Self.slideDistance, dy: 0), display: false)
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        panel.makeKey()
        presentation.isVisible = true

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.22
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrame(target, display: true)
            panel.animator().alphaValue = 1
        } completionHandler: { [weak self] in
            Task { @MainActor in self?.panel.invalidateShadow() }
        }
        installMonitors()
    }

    func hide() {
        guard presentation.isVisible else { return }
        presentation.isVisible = false
        removeMonitors()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().setFrame(panel.frame.offsetBy(dx: Self.slideDistance, dy: 0), display: true)
            panel.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            Task { @MainActor in
                guard let self, !self.presentation.isVisible else { return }
                self.panel.orderOut(nil)
            }
        }
    }

    // MARK: - Private

    private static func frame(on screen: NSScreen) -> NSRect {
        let visible = screen.visibleFrame
        return NSRect(
            x: visible.maxX - width - margin,
            y: visible.minY + margin,
            width: width,
            height: visible.height - margin * 2
        )
    }

    /// Stretchable rounded-rect mask; the window shadow follows it.
    private static func roundedMask(radius: CGFloat) -> NSImage {
        let edge = radius * 2 + 1
        let image = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }

    private func installMonitors() {
        removeMonitors()
        // Clicks in other apps close the sidebar. Clicks on our own status item go to its button instead.
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in self?.hide() }
        }
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.reposition() }
        }
    }

    private func removeMonitors() {
        if let clickMonitor {
            NSEvent.removeMonitor(clickMonitor)
        }
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
        }
        clickMonitor = nil
        screenObserver = nil
    }

    private func reposition() {
        guard presentation.isVisible else { return }
        let screen = NSScreen.screens.first { $0 == self.screen } ?? NSScreen.main
        guard let screen else { return }
        panel.setFrame(Self.frame(on: screen), display: true)
    }
}
