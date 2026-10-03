import SwiftUI

struct DurationChips: View {
    let selected: AwakeDuration
    let onSelect: (AwakeDuration) -> Void

    var body: some View {
        HStack(spacing: 6) {
            ForEach(AwakeDuration.allCases) { duration in
                Button(duration.label) { onSelect(duration) }
                    .buttonStyle(ChipButtonStyle(isSelected: duration == selected))
                    .accessibilityLabel(duration.spokenLabel)
            }
        }
    }
}

struct StatRow: View {
    let symbol: String
    let title: String
    let value: String
    var tint: Color = .secondary

    var body: some View {
        HStack(spacing: 10) {
            RowIcon(symbol: symbol)
            Text(title)
                .font(.system(size: 12))
            Spacer()
            Text(value)
                .font(.system(size: 12, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(tint)
        }
        .padding(.vertical, 5)
    }
}

/// A switch drawn in SwiftUI so it matches the accent and renders in snapshots.
struct SettingToggle: View {
    let symbol: String
    let title: String
    @Binding var isOn: Bool

    var body: some View {
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { isOn.toggle() }
        } label: {
            HStack(spacing: 10) {
                RowIcon(symbol: symbol)
                Text(title)
                    .font(.system(size: 12))
                    .foregroundStyle(.primary)
                Spacer()
                Capsule()
                    .fill(isOn ? Color.ember : Color.primary.opacity(0.14))
                    .frame(width: 30, height: 18)
                    .overlay(alignment: isOn ? .trailing : .leading) {
                        Circle()
                            .fill(.white)
                            .shadow(color: .black.opacity(0.18), radius: 1, y: 0.5)
                            .padding(2)
                    }
            }
            .padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(isOn ? "On" : "Off")
    }
}

struct MiniStepper: View {
    @Binding var value: Int
    let range: ClosedRange<Int>
    let step: Int
    let format: (Int) -> String

    var body: some View {
        HStack(spacing: 0) {
            stepButton("minus", enabled: value > range.lowerBound) {
                value = max(range.lowerBound, value - step)
            }
            Text(format(value))
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .monospacedDigit()
                .frame(width: 36)
            stepButton("plus", enabled: value < range.upperBound) {
                value = min(range.upperBound, value + step)
            }
        }
        .background(Capsule().fill(Color.primary.opacity(0.06)))
    }

    private func stepButton(_ symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 9, weight: .bold))
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(enabled ? HierarchicalShapeStyle.primary : .tertiary)
        .disabled(!enabled)
    }
}

struct RowIcon: View {
    let symbol: String

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .frame(width: 18)
    }
}

struct SetupCard: View {
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("One-time setup", systemImage: "lock.shield")
                .font(.system(size: 12, weight: .semibold))
            Text("Approve once with your password. Stowaway can then switch sleep on and off instantly, and always turn it back off by itself, even in your bag.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button(action: action) {
                Text("Authorize…")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Color.ember))
            }
            .buttonStyle(.plain)
            .padding(.top, 2)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.primary.opacity(0.05)))
    }
}
