import SwiftUI

/// The hero toggle. Glows and breathes while the Mac is being kept awake.
struct PowerOrb: View {
    let isActive: Bool
    /// Pauses the breathing animation while the sidebar is hidden.
    let animates: Bool
    var size: CGFloat = 148
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !(isActive && animates))) { timeline in
                let phase = (sin(timeline.date.timeIntervalSinceReferenceDate * 2 * .pi / 2.8) + 1) / 2
                orb(glow: isActive ? 0.65 + 0.35 * phase : 0)
            }
        }
        .buttonStyle(OrbPressStyle())
        .accessibilityLabel(isActive ? "Let the Mac sleep normally" : "Keep the Mac awake with the lid closed")
    }

    private func orb(glow: Double) -> some View {
        ZStack {
            Circle()
                .fill(Color.ember)
                .blur(radius: 30)
                .opacity(0.55 * glow)
                .scaleEffect(1 + 0.1 * glow)

            Circle()
                .fill(isActive
                    ? AnyShapeStyle(LinearGradient(colors: [.emberLight, .ember], startPoint: .topLeading, endPoint: .bottomTrailing))
                    : AnyShapeStyle(Color.primary.opacity(0.04)))

            Circle()
                .strokeBorder(isActive ? Color.white.opacity(0.30) : Color.primary.opacity(0.12), lineWidth: 1)

            Circle()
                .strokeBorder(isActive ? Color.white.opacity(0.16) : Color.primary.opacity(0.06), lineWidth: 1)
                .padding(size * 0.11)

            Image(systemName: "power")
                .font(.system(size: size * 0.27, weight: .light))
                .foregroundStyle(isActive ? Color.white : Color.secondary)
        }
        .frame(width: size, height: size)
        .contentShape(Circle())
    }
}

private struct OrbPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}
