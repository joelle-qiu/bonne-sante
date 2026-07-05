import SwiftUI

/// 首页周期面板：阶段（含 Apple 健康来源）+ 饮食/训练建议，单卡片呈现
/// @author jiali.qiu
struct HomeCyclePanel: View {
    let phaseInfo: CycleEngine.PhaseInfo

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.elderModeEnabled) private var elderModeEnabled

    var body: some View {
        VStack(alignment: .leading, spacing: elderModeEnabled ? 12 : 10) {
            PhaseBar(
                label: phaseInfo.label,
                phase: phaseInfo.phase,
                daysUntilNextPeriod: phaseInfo.daysUntilNextPeriod,
                dataSourceLabel: phaseInfo.phase == .unknown ? nil : phaseInfo.dataSource.label,
                embedded: true
            )

            if showsDivider {
                Divider()
                    .overlay(Theme.phaseBarBorder(phaseInfo.phase, colorScheme).opacity(0.55))
            }

            if phaseInfo.phase == .unknown {
                if !phaseInfo.tip.isEmpty {
                    unknownPhaseTip
                }
            } else {
                CycleTipsCard(phaseInfo: phaseInfo, compact: true, embedded: true)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, elderModeEnabled ? 14 : 12)
        .background(Theme.phaseBarBackground(phaseInfo.phase, colorScheme))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.cornerRadiusCard)
                .strokeBorder(Theme.phaseBarBorder(phaseInfo.phase, colorScheme), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadiusCard))
        .animation(.easeInOut(duration: 0.35), value: phaseInfo.phase)
    }

    private var showsDivider: Bool {
        if phaseInfo.phase == .unknown {
            return !phaseInfo.tip.isEmpty
        }
        return true
    }

    private var unknownPhaseTip: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "sparkles")
                .font(.caption)
                .foregroundStyle(Theme.phaseAccent(phaseInfo.phase, colorScheme))
            Text(phaseInfo.tip)
                .font(.caption)
                .foregroundStyle(Theme.adaptiveTextSecondary(colorScheme))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }
}

#Preview {
    VStack(spacing: 16) {
        HomeCyclePanel(
            phaseInfo: CycleEngine.PhaseInfo(
                phase: .follicular,
                cycleDay: 6,
                label: "卵泡期 · 第6天",
                tip: "",
                dietTip: "适量优质蛋白与复合碳水，为下一阶段的训练储备能量。",
                workoutTip: "适合逐步增加力量与有氧强度。",
                dataSource: .healthKit,
                daysUntilNextPeriod: 25,
                predictedNextPeriodStart: nil
            )
        )
    }
    .padding()
    .background(Theme.background)
}
