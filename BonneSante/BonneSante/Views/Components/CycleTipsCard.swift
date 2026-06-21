import SwiftUI

/// 周期饮食 & 训练 tips 卡片（阶段三知识库）
/// @author jiali.qiu
struct CycleTipsCard: View {
    let phaseInfo: CycleEngine.PhaseInfo
    var compact: Bool = false

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 8 : 12) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .foregroundStyle(Theme.phaseAccent(phaseInfo.phase, colorScheme))
                Text("周期建议")
                    .font(compact ? .subheadline.weight(.semibold) : .headline)
                    .foregroundStyle(Theme.adaptiveTextPrimary(colorScheme))
                Spacer()
                Text(phaseInfo.dataSource.label)
                    .font(.caption2)
                    .foregroundStyle(Theme.adaptiveTextSecondary(colorScheme))
            }

            tipRow(icon: "fork.knife", title: "饮食", text: phaseInfo.dietTip)
            tipRow(icon: "figure.run", title: "训练", text: phaseInfo.workoutTip)
        }
        .padding(compact ? 12 : 16)
        .background(Theme.phaseBarBackground(phaseInfo.phase, colorScheme))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.cornerRadiusCard)
                .strokeBorder(Theme.phaseBarBorder(phaseInfo.phase, colorScheme), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadiusCard))
    }

    private func tipRow(icon: String, title: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(Theme.phaseAccent(phaseInfo.phase, colorScheme))
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.adaptiveTextSecondary(colorScheme))
                Text(text)
                    .font(compact ? .caption : .subheadline)
                    .foregroundStyle(Theme.adaptiveTextPrimary(colorScheme))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

#Preview {
    CycleTipsCard(
        phaseInfo: CycleEngine.PhaseInfo(
            phase: .luteal,
            cycleDay: 18,
            label: "黄体期 · 第18天",
            tip: "",
            dietTip: "黄体期易馋甜食，用坚果、酸奶替代高糖零食。",
            workoutTip: "降低高强度训练，瑜伽和快走更友好。",
            dataSource: .healthKit,
            daysUntilNextPeriod: 10,
            predictedNextPeriodStart: nil
        )
    )
    .padding()
}
