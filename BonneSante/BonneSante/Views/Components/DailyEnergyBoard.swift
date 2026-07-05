import SwiftUI

/// 今日能量看板：三环分别表示 摄入 / 训练 / 消耗 的目标 vs 实际
/// @author jiali.qiu
struct DailyEnergyBoard: View {
    let remaining: Double
    /// 今日预算摄入
    let budget: Double
    /// 今日已摄入
    let consumed: Double
    /// 今日应消耗（基础代谢 + 计划运动）
    let expectedBurn: Double
    /// 今日已消耗（HealthKit 基础 + 活动）
    let actualBurn: Double
    /// 今日健身计划消耗目标
    let plannedWorkoutBurn: Double
    /// 今日已活动消耗
    let actualWorkoutBurn: Double
    let isRestDay: Bool
    let isUsingWatchData: Bool
    /// 休息日参考活动（7 日均值）
    var restDayActivityReference: Double? = nil

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.elderModeEnabled) private var elderModeEnabled

    private var intakeProgress: Double {
        guard budget > 0 else { return 0 }
        return min(consumed / budget, 1)
    }

    private var workoutGoal: Double {
        if plannedWorkoutBurn > 0 { return plannedWorkoutBurn }
        return max(restDayActivityReference ?? 300, 200)
    }

    private var workoutProgress: Double {
        guard workoutGoal > 0 else { return 0 }
        return min(actualWorkoutBurn / workoutGoal, 1)
    }

    private var burnProgress: Double {
        guard expectedBurn > 0 else { return 0 }
        return min(actualBurn / expectedBurn, 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: elderModeEnabled ? 20 : 16) {
            headerRow
            heroSection
            ringLegend
            metricTiles
            footerSummary
        }
        .morandiCard()
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var heroSection: some View {
        if elderModeEnabled {
            VStack(spacing: 16) {
                activityRings
                    .frame(maxWidth: .infinity)
                heroMetric
            }
        } else {
            HStack(alignment: .center, spacing: 20) {
                activityRings
                heroMetric
            }
        }
    }

    private var headerRow: some View {
        Group {
            if elderModeEnabled {
                VStack(alignment: .leading, spacing: 8) {
                    Text("今日能量")
                        .font(.headline)
                        .foregroundStyle(Theme.adaptiveTextPrimary(colorScheme))
                    watchBadge
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                HStack {
                    Text("今日能量")
                        .font(.headline)
                        .foregroundStyle(Theme.adaptiveTextPrimary(colorScheme))
                    Spacer()
                    watchBadge
                }
            }
        }
    }

    @ViewBuilder
    private var watchBadge: some View {
        if isUsingWatchData {
            Label("Apple 健康", systemImage: "applewatch")
                .font(.caption.weight(.medium))
                .foregroundStyle(Theme.adaptiveTextSecondary(colorScheme))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Theme.brandPrimary(colorScheme).opacity(colorScheme == .dark ? 0.22 : 0.35))
                .clipShape(Capsule())
        } else {
            Text("估算模式")
                .font(.caption.weight(.medium))
                .foregroundStyle(Theme.adaptiveTextSecondary(colorScheme))
        }
    }

    private var activityRings: some View {
        let ringScale: CGFloat = elderModeEnabled ? 0.92 : 1.0
        return ZStack {
            ActivityRing(
                progress: burnProgress,
                color: Theme.energyBasal(colorScheme),
                lineWidth: 10,
                diameter: 132 * ringScale
            )
            ActivityRing(
                progress: intakeProgress,
                color: Theme.energyConsumed(colorScheme),
                lineWidth: 10,
                diameter: 104 * ringScale
            )
            ActivityRing(
                progress: workoutProgress,
                color: Theme.energyActive(colorScheme),
                lineWidth: 10,
                diameter: 76 * ringScale
            )
        }
        .frame(width: 140 * ringScale, height: 140 * ringScale)
        .accessibilityLabel(
            "摄入 \(Int(consumed)) 预算 \(Int(budget))，训练 \(Int(actualWorkoutBurn)) 计划 \(Int(plannedWorkoutBurn))，消耗 \(Int(actualBurn)) 应消耗 \(Int(expectedBurn))"
        )
    }

    private var heroMetric: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(remaining > 0 ? "还可摄入" : "已超出")
                .font(.subheadline)
                .foregroundStyle(Theme.adaptiveTextSecondary(colorScheme))
            Text("\(Int(abs(remaining)).formatted())")
                .font(elderModeEnabled ? .system(.largeTitle, design: .rounded).weight(.bold) : .system(size: 42, weight: .bold, design: .rounded))
                .foregroundStyle(remaining > 0 ? Theme.adaptiveTextPrimary(colorScheme) : Theme.adaptiveWarning(colorScheme))
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            Text("大卡")
                .font(.caption)
                .foregroundStyle(Theme.adaptiveTextSecondary(colorScheme))
            Text("预算 \(Int(budget).formatted()) · 已摄入 \(Int(consumed).formatted())")
                .font(.caption2)
                .foregroundStyle(Theme.adaptiveTextSecondary(colorScheme))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var ringLegend: some View {
        VStack(alignment: .leading, spacing: 6) {
            ringLegendRow(
                color: Theme.energyConsumed(colorScheme),
                title: "摄入",
                detail: "\(Int(consumed)) / \(Int(budget)) kcal"
            )
            ringLegendRow(
                color: Theme.energyActive(colorScheme),
                title: isRestDay ? "活动" : "训练",
                detail: workoutLegendDetail
            )
            ringLegendRow(
                color: Theme.energyBasal(colorScheme),
                title: "消耗",
                detail: "\(Int(actualBurn)) / \(Int(expectedBurn)) kcal"
            )
        }
    }

    private var workoutLegendDetail: String {
        if plannedWorkoutBurn > 0 {
            return "\(Int(actualWorkoutBurn)) / \(Int(plannedWorkoutBurn)) kcal"
        }
        if isRestDay {
            return "休息日 · 已活动 \(Int(actualWorkoutBurn)) kcal"
        }
        return "\(Int(actualWorkoutBurn)) kcal"
    }

    private func ringLegendRow(color: Color, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
                .padding(.top, elderModeEnabled ? 4 : 0)
            Text(title)
                .font(elderModeEnabled ? .caption.weight(.semibold) : .caption2.weight(.semibold))
                .foregroundStyle(Theme.adaptiveTextPrimary(colorScheme))
            Text(detail)
                .font(elderModeEnabled ? .caption : .caption2)
                .foregroundStyle(Theme.adaptiveTextSecondary(colorScheme))
                .monospacedDigit()
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var metricTiles: some View {
        let intake = EnergyMetricTile(
            title: "已摄入",
            value: Int(consumed),
            goal: Int(budget),
            unit: "kcal",
            color: Theme.energyConsumed(colorScheme),
            icon: "fork.knife",
            caption: "今日饮食",
            compact: !elderModeEnabled
        )
        let workout = EnergyMetricTile(
            title: isRestDay ? "已活动" : "已训练",
            value: Int(actualWorkoutBurn),
            goal: Int(workoutGoal),
            unit: "kcal",
            color: Theme.energyActive(colorScheme),
            icon: "figure.run",
            caption: isRestDay ? "休息日参考" : "计划 \(Int(plannedWorkoutBurn))",
            compact: !elderModeEnabled
        )
        let burn = EnergyMetricTile(
            title: "已消耗",
            value: Int(actualBurn),
            goal: Int(expectedBurn),
            unit: "kcal",
            color: Theme.energyBasal(colorScheme),
            icon: "flame.fill",
            caption: isUsingWatchData ? "基础 + 活动" : "估算模式",
            compact: !elderModeEnabled
        )

        if elderModeEnabled {
            VStack(spacing: 10) {
                intake
                workout
                burn
            }
        } else {
            HStack(alignment: .top, spacing: 10) {
                intake
                workout
                burn
            }
        }
    }

    private var footerSummary: some View {
        Group {
            if elderModeEnabled {
                VStack(alignment: .leading, spacing: 6) {
                    Label("应消耗 \(Int(expectedBurn).formatted()) kcal", systemImage: "flame.fill")
                    Text("已消耗 \(Int(actualBurn).formatted()) kcal")
                        .monospacedDigit()
                }
                .font(.caption)
                .foregroundStyle(Theme.adaptiveTextSecondary(colorScheme))
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                HStack {
                    Label("应消耗 \(Int(expectedBurn).formatted()) kcal", systemImage: "flame.fill")
                        .font(.caption)
                        .foregroundStyle(Theme.adaptiveTextSecondary(colorScheme))
                    Spacer()
                    Text("已消耗 \(Int(actualBurn).formatted()) kcal")
                        .font(.caption)
                        .foregroundStyle(Theme.adaptiveTextSecondary(colorScheme))
                }
            }
        }
    }
}

// MARK: - Activity Ring

private struct ActivityRing: View {
    let progress: Double
    let color: Color
    let lineWidth: CGFloat
    let diameter: CGFloat

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Circle()
            .stroke(color.opacity(colorScheme == .dark ? 0.2 : 0.28), lineWidth: lineWidth)
            .frame(width: diameter, height: diameter)
            .overlay {
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.spring(duration: 0.55), value: progress)
            }
    }
}

// MARK: - Metric Tile

private struct EnergyMetricTile: View {
    let title: String
    let value: Int
    let goal: Int
    let unit: String
    let color: Color
    let icon: String
    var caption: String = ""
    var compact: Bool = true

    @Environment(\.colorScheme) private var colorScheme

    private static let captionMinHeight: CGFloat = 24

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 6 : 8) {
            HStack(spacing: compact ? 4 : 6) {
                Image(systemName: icon)
                    .font(compact ? .caption2 : .caption)
                    .foregroundStyle(color)
                    .frame(width: compact ? 14 : 18, alignment: .center)
                Text(title)
                    .font(compact ? .caption2.weight(.medium) : .subheadline.weight(.medium))
                    .foregroundStyle(Theme.adaptiveTextSecondary(colorScheme))
                    .lineLimit(compact ? 1 : 2)
                    .minimumScaleFactor(0.85)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if compact {
                Text("\(value)/\(goal)")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(Theme.adaptiveTextPrimary(colorScheme))
                    .minimumScaleFactor(0.8)
                    .lineLimit(1)
                    .monospacedDigit()
                    .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)

                Text(unit)
                    .font(.caption2)
                    .foregroundStyle(Theme.adaptiveTextSecondary(colorScheme))
                    .frame(maxWidth: .infinity, minHeight: 14, alignment: .leading)
            } else {
                Text("\(value)/\(goal)")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(Theme.adaptiveTextPrimary(colorScheme))
                    .minimumScaleFactor(0.8)
                    .lineLimit(1)
                    .monospacedDigit()
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text(unit)
                    .font(.caption)
                    .foregroundStyle(Theme.adaptiveTextSecondary(colorScheme))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Text(caption)
                .font(compact ? .system(size: 9) : .caption)
                .foregroundStyle(Theme.adaptiveTextSecondary(colorScheme))
                .lineLimit(compact ? 2 : 3)
                .minimumScaleFactor(0.85)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, minHeight: compact ? Self.captionMinHeight : nil, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(compact ? 10 : 14)
        .background(color.opacity(colorScheme == .dark ? 0.14 : 0.22))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

#Preview("浅色") {
    DailyEnergyBoard(
        remaining: 1250,
        budget: 1800,
        consumed: 550,
        expectedBurn: 2100,
        actualBurn: 980,
        plannedWorkoutBurn: 320,
        actualWorkoutBurn: 180,
        isRestDay: false,
        isUsingWatchData: true
    )
    .padding()
    .background(Theme.background)
    .preferredColorScheme(.light)
}

#Preview("长辈版") {
    DailyEnergyBoard(
        remaining: 1250,
        budget: 1800,
        consumed: 550,
        expectedBurn: 2100,
        actualBurn: 980,
        plannedWorkoutBurn: 320,
        actualWorkoutBurn: 180,
        isRestDay: false,
        isUsingWatchData: true
    )
    .padding()
    .background(Theme.background)
    .preferredColorScheme(.light)
    .environment(\.elderModeEnabled, true)
    .dynamicTypeSize(.accessibility2)
}

#Preview("深色") {
    DailyEnergyBoard(
        remaining: 1250,
        budget: 1800,
        consumed: 550,
        expectedBurn: 2100,
        actualBurn: 980,
        plannedWorkoutBurn: 0,
        actualWorkoutBurn: 220,
        isRestDay: true,
        isUsingWatchData: true,
        restDayActivityReference: 400
    )
    .padding()
    .background(Theme.backgroundDark)
    .preferredColorScheme(.dark)
}
