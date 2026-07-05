import SwiftUI

/// 本周营养目标条：按日展示微调后热量，训练日以图标标记
/// @author jiali.qiu
struct WeeklyNutritionStrip: View {
    enum DisplayMode {
        /// 营养 Tab：全周 7 日，训练/休息按排课区分
        case fullWeek
        /// 训练计划页：仅展示有排课的训练日
        case scheduleAligned
    }

    let days: [WorkoutNutritionPlanner.WeeklyNutritionDay]
    var compact: Bool = false
    var baselineCalories: Double?
    var displayMode: DisplayMode = .fullWeek
    var restDaySummary: (count: Int, calories: Int)?

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 8 : 10) {
            if !compact, let baselineCalories, baselineCalories > 0 {
                Text(subtitleText(baseline: Int(baselineCalories)))
                    .font(.caption2)
                    .foregroundStyle(Theme.adaptiveTextSecondary(colorScheme))
            }

            HStack(spacing: compact ? 4 : 6) {
                ForEach(days) { day in
                    dayCell(day)
                }
            }

            if displayMode == .scheduleAligned, let rest = restDaySummary {
                HStack(spacing: 6) {
                    Image(systemName: "moon.zzz")
                        .font(.caption2)
                    Text("其余 \(rest.count) 天 · 休息日 \(rest.calories) kcal/天")
                        .font(.caption2)
                }
                .foregroundStyle(Theme.adaptiveTextSecondary(colorScheme))
            }

            if !compact {
                HStack(spacing: 12) {
                    if displayMode == .scheduleAligned {
                        legendItem(symbol: "figure.run", label: "排课日")
                        Text("非排课日按休息日目标 · 今日高亮见首页")
                            .font(.caption2)
                            .foregroundStyle(Theme.adaptiveTextSecondary(colorScheme))
                    } else {
                        legendItem(symbol: "figure.run", label: "训练日")
                        legendItem(symbol: "moon.zzz", label: "休息日")
                        Text("今日高亮 · 摄入对比见首页")
                            .font(.caption2)
                            .foregroundStyle(Theme.adaptiveTextSecondary(colorScheme))
                    }
                }
            }
        }
    }

    private func subtitleText(baseline: Int) -> String {
        switch displayMode {
        case .fullWeek:
            return "基于减脂建议 \(baseline) kcal/天，按训练排课微调"
        case .scheduleAligned:
            return "训练日目标（基于减脂建议 \(baseline) kcal/天微调）"
        }
    }

    private func dayCell(_ day: WorkoutNutritionPlanner.WeeklyNutritionDay) -> some View {
        VStack(spacing: compact ? 3 : 5) {
            Text(day.weekdayShort)
                .font(compact ? .caption2 : .caption)
                .foregroundStyle(day.isToday
                    ? Theme.adaptiveAccent(colorScheme)
                    : Theme.adaptiveTextSecondary(colorScheme))

            Text("\(Int(day.plan.caloriesKcal))")
                .font(compact ? .caption.weight(.semibold) : .subheadline.weight(.semibold))
                .foregroundStyle(Theme.adaptiveTextPrimary(colorScheme))
                .minimumScaleFactor(0.7)
                .lineLimit(1)

            Image(systemName: day.isTrainingDay ? "figure.run" : "moon.zzz")
                .font(.caption2)
                .foregroundStyle(day.isTrainingDay
                    ? Theme.adaptiveAccent(colorScheme)
                    : Theme.adaptiveTextSecondary(colorScheme).opacity(0.7))

            if let delta = day.calorieDeltaFromBaseline {
                Text(delta > 0 ? "+\(delta)" : "\(delta)")
                    .fixedFont(size: 9, weight: .medium)
                    .foregroundStyle(delta > 0
                        ? Theme.macroCarbs(colorScheme)
                        : Theme.adaptiveTextSecondary(colorScheme))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, compact ? 6 : 8)
        .padding(.horizontal, 2)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(day.isToday
                    ? Theme.adaptiveAccent(colorScheme).opacity(colorScheme == .dark ? 0.16 : 0.12)
                    : Theme.adaptiveTextSecondary(colorScheme).opacity(colorScheme == .dark ? 0.08 : 0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(day.isToday ? Theme.adaptiveAccent(colorScheme).opacity(0.55) : Color.clear, lineWidth: 1)
        )
    }

    private func legendItem(symbol: String, label: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: symbol)
                .font(.caption2)
            Text(label)
                .font(.caption2)
        }
        .foregroundStyle(Theme.adaptiveTextSecondary(colorScheme))
    }
}

#Preview {
    let weekStart = WorkoutPlanService.startOfWeek()
    let days = WorkoutNutritionPlanner.weeklyNutritionDays(
        prefs: WorkoutPlanPreferences(
            dailyCalorieTargetKcal: 1730,
            dailyProteinGrams: 110,
            dailyCarbGrams: 165,
            dailyFatGrams: 55,
            nutritionPlanSource: "ai",
            restDayCalorieTargetKcal: 1530,
            restDayProteinGrams: 110,
            restDayCarbGrams: 120,
            restDayFatGrams: 55
        ),
        weekEntries: [],
        weekStart: weekStart,
        baselineCalories: 1650
    )
    WeeklyNutritionStrip(days: days, baselineCalories: 1650)
        .padding()
        .background(Theme.background)
}
