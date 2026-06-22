import SwiftUI

/// 今日能量看板（参考 Apple 健康布局 + 莫兰迪配色）
/// @author jiali.qiu
struct DailyEnergyBoard: View {
    let remaining: Double
    let budget: Double
    let consumed: Double
    let activeEnergy: Double
    let basalEnergy: Double
    let totalBurned: Double
    let isUsingWatchData: Bool
    /// 智能 BMR 来源（如「Watch 7日均值」）
    var bmrSourceLabel: String? = nil
    /// TDEE 来源短标签
    var tdeeSourceLabel: String? = nil
    /// 今日 Watch 活动消耗（与 7 日均值对照）
    var todayActiveEnergy: Double? = nil
    /// 活动消耗基准说明（如「7日均值」）
    var activeSourceLabel: String? = nil

    @Environment(\.colorScheme) private var colorScheme

    private var activeGoal: Double { max(activeEnergy * 1.2, 400) }
    private var consumedProgress: Double {
        guard budget > 0 else { return 0 }
        return min(consumed / budget, 1)
    }
    private var activeProgress: Double {
        guard activeGoal > 0 else { return 0 }
        return min(activeEnergy / activeGoal, 1)
    }
    private var basalShare: Double {
        guard totalBurned > 0 else { return 0.65 }
        return min(basalEnergy / totalBurned, 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            headerRow
            HStack(alignment: .center, spacing: 20) {
                activityRings
                heroMetric
            }
            metricTiles
            footerSummary
        }
        .morandiCard()
        .accessibilityElement(children: .contain)
    }

    private var headerRow: some View {
        HStack {
            Text("今日能量")
                .font(.headline)
                .foregroundStyle(Theme.adaptiveTextPrimary(colorScheme))
            Spacer()
            if let bmrSourceLabel, !bmrSourceLabel.isEmpty {
                Label("BMR · \(bmrSourceLabel)", systemImage: "applewatch")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Theme.adaptiveTextSecondary(colorScheme))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Theme.brandPrimary(colorScheme).opacity(colorScheme == .dark ? 0.22 : 0.35))
                    .clipShape(Capsule())
            } else if isUsingWatchData {
                Label("Apple Watch", systemImage: "applewatch")
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
    }

    private var activityRings: some View {
        ZStack {
            ActivityRing(
                progress: basalShare,
                color: Theme.energyBasal(colorScheme),
                lineWidth: 10,
                diameter: 132
            )
            ActivityRing(
                progress: consumedProgress,
                color: Theme.energyConsumed(colorScheme),
                lineWidth: 10,
                diameter: 104
            )
            ActivityRing(
                progress: activeProgress,
                color: Theme.energyActive(colorScheme),
                lineWidth: 10,
                diameter: 76
            )
        }
        .frame(width: 140, height: 140)
        .accessibilityLabel("活动 \(Int(activeEnergy))、已摄入 \(Int(consumed))、基础 \(Int(basalEnergy)) 大卡")
    }

    private var heroMetric: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(remaining > 0 ? "还可摄入" : "已超出")
                .font(.subheadline)
                .foregroundStyle(Theme.adaptiveTextSecondary(colorScheme))
            Text("\(Int(abs(remaining)).formatted())")
                .font(.system(size: 42, weight: .bold, design: .rounded))
                .foregroundStyle(remaining > 0 ? Theme.adaptiveTextPrimary(colorScheme) : Theme.adaptiveWarning(colorScheme))
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            Text("大卡")
                .font(.caption)
                .foregroundStyle(Theme.adaptiveTextSecondary(colorScheme))
            Text("预算 \(Int(budget).formatted())")
                .font(.caption2)
                .foregroundStyle(Theme.adaptiveTextSecondary(colorScheme))
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var metricTiles: some View {
        HStack(spacing: 10) {
            EnergyMetricTile(
                title: "活动",
                value: Int(activeEnergy),
                unit: "大卡",
                color: Theme.energyActive(colorScheme),
                icon: "figure.run",
                caption: activeSourceLabel
            )
            EnergyMetricTile(
                title: "基础",
                value: Int(basalEnergy),
                unit: "大卡",
                color: Theme.energyBasal(colorScheme),
                icon: "bed.double.fill",
                caption: bmrSourceLabel
            )
            EnergyMetricTile(
                title: "已摄入",
                value: Int(consumed),
                unit: "大卡",
                color: Theme.energyConsumed(colorScheme),
                icon: "fork.knife"
            )
        }
    }

    private var footerSummary: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Label("日均总消耗 \(Int(totalBurned).formatted())", systemImage: "flame.fill")
                    .font(.caption)
                    .foregroundStyle(Theme.adaptiveTextSecondary(colorScheme))
                if let tdeeSourceLabel {
                    Text("· \(tdeeSourceLabel)")
                        .font(.caption2)
                        .foregroundStyle(Theme.adaptiveTextSecondary(colorScheme))
                }
                Spacer()
                Text("已摄入 \(Int(consumed).formatted()) 大卡")
                    .font(.caption)
                    .foregroundStyle(Theme.adaptiveTextSecondary(colorScheme))
            }
            if let todayActiveEnergy, abs(todayActiveEnergy - activeEnergy) > 15 {
                Text("今日活动 \(Int(todayActiveEnergy).formatted()) 大卡 · 活动基准 \(Int(activeEnergy).formatted()) 大卡/天")
                    .font(.caption2)
                    .foregroundStyle(Theme.adaptiveTextSecondary(colorScheme))
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
    let unit: String
    let color: Color
    let icon: String
    var caption: String? = nil

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.caption2)
                    .foregroundStyle(color)
                Text(title)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(Theme.adaptiveTextSecondary(colorScheme))
            }
            Text(value.formatted())
                .font(.title3.weight(.bold))
                .foregroundStyle(Theme.adaptiveTextPrimary(colorScheme))
                .minimumScaleFactor(0.8)
                .lineLimit(1)
            Text(unit)
                .font(.caption2)
                .foregroundStyle(Theme.adaptiveTextSecondary(colorScheme))
            if let caption, !caption.isEmpty {
                Text(caption)
                    .font(.system(size: 9))
                    .foregroundStyle(Theme.adaptiveTextSecondary(colorScheme))
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(color.opacity(colorScheme == .dark ? 0.14 : 0.22))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

#Preview("浅色") {
    DailyEnergyBoard(
        remaining: 1250,
        budget: 1800,
        consumed: 550,
        activeEnergy: 448,
        basalEnergy: 1393,
        totalBurned: 1841,
        isUsingWatchData: true
    )
    .padding()
    .background(Theme.background)
    .preferredColorScheme(.light)
}

#Preview("深色") {
    DailyEnergyBoard(
        remaining: 1250,
        budget: 1800,
        consumed: 550,
        activeEnergy: 448,
        basalEnergy: 1393,
        totalBurned: 1841,
        isUsingWatchData: true
    )
    .padding()
    .background(Theme.backgroundDark)
    .preferredColorScheme(.dark)
}
