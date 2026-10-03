import SwiftUI

extension Color {
    /// Terracotta, the one accent in the UI.
    static let ember = Color(red: 0.851, green: 0.467, blue: 0.341)
    static let emberLight = Color(red: 0.941, green: 0.627, blue: 0.494)
}

struct SectionLabel: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .tracking(1.2)
            .foregroundStyle(.tertiary)
    }
}

struct ChipButtonStyle: ButtonStyle {
    var isSelected = false
    var compact = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: compact ? 10.5 : 12, weight: .medium, design: .rounded))
            .foregroundStyle(isSelected ? Color.primary : Color.secondary)
            .padding(.horizontal, compact ? 8 : 11)
            .padding(.vertical, compact ? 3 : 6)
            .background(Capsule().fill(Color.primary.opacity(isSelected ? 0.10 : configuration.isPressed ? 0.06 : 0)))
            .overlay(Capsule().strokeBorder(Color.primary.opacity(isSelected ? 0 : 0.10), lineWidth: 1))
            .contentShape(Capsule())
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.easeOut(duration: 0.15), value: isSelected)
    }
}
