import SwiftUI

/// 今日营养条形可视化（莫兰迪配色）
/// 进度条按减脂计划宏量目标计算百分比；无目标时回退为三项相对比例。
/// @author jiali.qiu
struct NutritionMacroBars: View {
    let protein: Double
    let carbs: Double
    let fat: Double
    let calories: Double
    var proteinTarget: Double?
    var carbsTarget: Double?
    var fatTarget: Double?
    /// 如「训练计划微调 · 训练日 · 较减脂建议 +80 kcal」
    var subtitle: String?

    @Environment(\.colorScheme) private var colorScheme

    private var hasPlanTargets: Bool {
        [proteinTarget, carbsTarget, fatTarget].compactMap { $0 }.contains { $0 > 0 }
    }

    private var maxMacro: Double {
        max(protein, carbs, fat, 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("今日营养")
                    .font(.headline)
                    .foregroundStyle(Theme.adaptiveTextPrimary(colorScheme))
                Spacer()
                Text("\(Int(calories).formatted()) 大卡")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.adaptiveTextSecondary(colorScheme))
            }

            if hasPlanTargets, let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(Theme.adaptiveTextSecondary(colorScheme))
            }

            macroRow(
                title: "蛋白质",
                value: protein,
                target: proteinTarget,
                unit: "g",
                color: Theme.macroProtein(colorScheme),
                icon: "bolt.fill"
            )
            macroRow(
                title: "碳水",
                value: carbs,
                target: carbsTarget,
                unit: "g",
                color: Theme.macroCarbs(colorScheme),
                icon: "leaf.fill"
            )
            macroRow(
                title: "脂肪",
                value: fat,
                target: fatTarget,
                unit: "g",
                color: Theme.macroFat(colorScheme),
                icon: "drop.fill"
            )
        }
        .morandiCard()
    }

    private func macroRow(
        title: String,
        value: Double,
        target: Double?,
        unit: String,
        color: Color,
        icon: String
    ) -> some View {
        let progress = progressRatio(value: value, target: target)
        let percent = Int((progress * 100).rounded())

        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label(title, systemImage: icon)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(color)
                Spacer()
                if let target, target > 0 {
                    Text("\(formatMacro(value))/\(formatMacro(target))\(unit) · \(percent)%")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.adaptiveTextPrimary(colorScheme))
                } else {
                    Text("\(formatMacro(value))\(unit)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.adaptiveTextPrimary(colorScheme))
                }
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(color.opacity(colorScheme == .dark ? 0.18 : 0.24))
                    Capsule()
                        .fill(color)
                        .frame(width: geo.size.width * CGFloat(min(progress, 1)))
                        .animation(Theme.Motion.progressSpring, value: value)
                }
            }
            .frame(height: 8)
        }
    }

    private func progressRatio(value: Double, target: Double?) -> Double {
        if let target, target > 0 {
            return value / target
        }
        return value / maxMacro
    }

    private func formatMacro(_ value: Double) -> String {
        value >= 10 ? "\(Int(value))" : String(format: "%.1f", value)
    }
}

#Preview("有计划目标") {
    NutritionMacroBars(
        protein: 42,
        carbs: 120,
        fat: 35,
        calories: 980,
        proteinTarget: 96,
        carbsTarget: 180,
        fatTarget: 50
    )
    .padding()
    .background(Theme.background)
    .preferredColorScheme(.light)
}

#Preview("无目标") {
    NutritionMacroBars(protein: 42, carbs: 120, fat: 35, calories: 980)
        .padding()
        .background(Theme.backgroundDark)
        .preferredColorScheme(.dark)
}
