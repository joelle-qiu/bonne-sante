import SwiftUI

/// 周期阶段条（阶段三：主题色联动 + 下次经期倒计时）
/// @author jiali.qiu
struct PhaseBar: View {
    let label: String
    let phase: CyclePhase
    var daysUntilNextPeriod: Int? = nil
    var dataSourceLabel: String? = nil
    /// 嵌入统一周期卡片时不再单独绘制背景与圆角
    var embedded: Bool = false

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.elderModeEnabled) private var elderModeEnabled

    var body: some View {
        Group {
            if elderModeEnabled {
                elderLayout
            } else {
                compactLayout
            }
        }
        .modifier(PhaseBarChromeModifier(phase: phase, embedded: embedded))
        .animation(.easeInOut(duration: 0.35), value: phase)
    }

    private var compactLayout: some View {
        HStack(spacing: 10) {
            phaseIcon
            labelColumn
            Spacer(minLength: 8)
            trailingBadges
        }
    }

    private var elderLayout: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                phaseIcon
                labelColumn
            }
            if phase != .unknown || dataSourceLabel != nil {
                HStack(spacing: 8) {
                    trailingBadges
                    Spacer(minLength: 0)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var phaseIcon: some View {
        Image(systemName: "moon.circle.fill")
            .font(elderModeEnabled ? .title2 : .body)
            .foregroundStyle(Theme.phaseAccent(phase, colorScheme))
    }

    private var labelColumn: some View {
        VStack(alignment: .leading, spacing: elderModeEnabled ? 4 : 2) {
            Text(label)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(Theme.adaptiveTextPrimary(colorScheme))
                .fixedSize(horizontal: false, vertical: true)

            if let daysUntilNextPeriod, phase != .unknown {
                Text(daysUntilNextPeriod == 0 ? "预计今天来潮" : "预计 \(daysUntilNextPeriod) 天后来潮")
                    .font(elderModeEnabled ? .caption : .caption2)
                    .foregroundStyle(Theme.adaptiveTextSecondary(colorScheme))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private var trailingBadges: some View {
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
                .font(elderModeEnabled ? .caption : .caption2)
                .foregroundStyle(Theme.adaptiveTextSecondary(colorScheme))
                .lineLimit(2)
                .minimumScaleFactor(0.9)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct PhaseBarChromeModifier: ViewModifier {
    let phase: CyclePhase
    let embedded: Bool

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.elderModeEnabled) private var elderModeEnabled

    func body(content: Content) -> some View {
        if embedded {
            content
        } else {
            content
                .padding(.horizontal, 16)
                .padding(.vertical, elderModeEnabled ? 14 : 12)
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
    VStack(spacing: 12) {
        PhaseBar(label: "黄体期 · 第18天", phase: .luteal, daysUntilNextPeriod: 10, dataSourceLabel: "Apple 健康")
        PhaseBar(label: "周期未设置", phase: .unknown)
    }
    .padding()
    .background(Theme.background)
    .environment(\.elderModeEnabled, true)
    .dynamicTypeSize(.accessibility2)
}
