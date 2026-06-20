import SwiftUI

/// 月经周期阶段条
/// @author jiali.qiu
struct PhaseBar: View {
    let label: String
    let phase: CyclePhase

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "moon.circle.fill")
                .foregroundStyle(Color(hex: phase.themeColorHex))

            Text(label)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(Theme.textPrimary)

            Spacer()

            if phase != .unknown {
                Text(phase.rawValue)
                    .font(.caption)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color(hex: phase.themeColorHex).opacity(0.5))
                    .clipShape(Capsule())
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadiusCard))
    }
}

#Preview {
    PhaseBar(label: "黄体期 · 第18天", phase: .luteal)
        .padding()
        .background(Theme.background)
}
