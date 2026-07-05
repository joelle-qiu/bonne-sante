import SwiftUI

/// 周期饮食 & 训练 tips 卡片（阶段三知识库）
/// @author jiali.qiu
struct CycleTipsCard: View {
    let phaseInfo: CycleEngine.PhaseInfo
    var compact: Bool = false
    /// 嵌入首页周期面板时不重复绘制卡片与「周期建议」标题
    var embedded: Bool = false

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 8 : 12) {
            if !embedded {
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
            }

            tipRow(icon: "fork.knife", title: "饮食", text: phaseInfo.dietTip)
            tipRow(icon: "figure.run", title: "训练", text: phaseInfo.workoutTip)
        }
        .modifier(CycleTipsCardChromeModifier(phase: phaseInfo.phase, compact: compact, embedded: embedded))
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

private struct CycleTipsCardChromeModifier: ViewModifier {
    let phase: CyclePhase
    let compact: Bool
    let embedded: Bool

    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        if embedded {
            content
        } else {
            content
                .padding(compact ? 12 : 16)
                .background(Theme.phaseBarBackground(phase, colorScheme))
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.cornerRadiusCard)
                        .strokeBorder(Theme.phaseBarBorder(phase, colorScheme), lineWidth: 1)
                }
                .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadiusCard))
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
