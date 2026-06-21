import SwiftUI

/// 周期阶段条（阶段三：主题色联动 + 下次经期倒计时）
/// @author jiali.qiu
struct PhaseBar: View {
    let label: String
    let phase: CyclePhase
    var daysUntilNextPeriod: Int? = nil
    var dataSourceLabel: String? = nil

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "moon.circle.fill")
                .foregroundStyle(Theme.phaseAccent(phase, colorScheme))

            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(Theme.adaptiveTextPrimary(colorScheme))

                if let daysUntilNextPeriod, phase != .unknown {
                    Text(daysUntilNextPeriod == 0 ? "预计今天来潮" : "预计 \(daysUntilNextPeriod) 天后来潮")
                        .font(.caption2)
                        .foregroundStyle(Theme.adaptiveTextSecondary(colorScheme))
                }
            }

            Spacer()

            if phase != .unknown {
                Text(phase.rawValue)
                    .font(.caption)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Theme.phaseBarBackground(phase, colorScheme))
                    .foregroundStyle(Theme.adaptiveTextPrimary(colorScheme))
                    .clipShape(Capsule())
            }

            if let dataSourceLabel {
                Text(dataSourceLabel)
                    .font(.caption2)
                    .foregroundStyle(Theme.adaptiveTextSecondary(colorScheme))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Theme.phaseBarBackground(phase, colorScheme))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.cornerRadiusCard)
                .strokeBorder(Theme.phaseBarBorder(phase, colorScheme), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadiusCard))
        .animation(.easeInOut(duration: 0.35), value: phase)
    }
}

#Preview {
    VStack(spacing: 12) {
        PhaseBar(label: "黄体期 · 第18天", phase: .luteal, daysUntilNextPeriod: 10, dataSourceLabel: "Apple 健康")
        PhaseBar(label: "周期未设置", phase: .unknown)
    }
    .padding()
    .background(Theme.background)
}
