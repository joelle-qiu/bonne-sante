import Foundation
import SwiftData

/// 训练计划偏好（每周频率、AI 饮食建议等）
/// @author jiali.qiu
@Model
final class WorkoutPlanPreferences {
    var id: UUID
    /// 每周训练次数 2–6
    var sessionsPerWeek: Int
    var dietAdviceText: String
    var weeklySummaryText: String
    /// engine | ai
    var lastGeneratedSource: String
    var weekStartDate: Date?
    /// 本周训练消耗目标（kcal，与减脂计划对齐）
    var weeklyBurnGoalKcal: Double
    /// 用户无法完成、需避开的动作（逗号分隔）
    var excludedExercisesText: String
    /// AI / 规则引擎生成的每日营养目标（与首页、营养 Tab 联动）
    var dailyCalorieTargetKcal: Double
    var dailyProteinGrams: Double
    var dailyCarbGrams: Double
    var dailyFatGrams: Double
    /// ai | engine
    var nutritionPlanSource: String
    var nutritionNotes: String
    /// 休息日营养目标（与训练日分日联动）
    var restDayCalorieTargetKcal: Double
    var restDayProteinGrams: Double
    var restDayCarbGrams: Double
    var restDayFatGrams: Double
    var restDayNotes: String
    /// 计划类型：balanced | threeDaySplit | glutesLegs | shouldersBack | cardioFocus
    var planTypeRaw: String
    /// 计划风格：professional | moodWeather
    var planStyleRaw: String
    /// 是否已根据 Apple 健康历史完成一次性偏好推断
    var inferredFromHealthKit: Bool
    /// Apple 健康锻炼习惯摘要（供 AI 与 UI 展示）
    var healthKitWorkoutSummaryText: String
    /// 心情模式：用户覆盖的 weekday→活动，如 `2:swimming,4:dance`
    var moodDayOverridesText: String
    /// 心情模式：用户手动固定的排课 weekday，如 `2,4`（空则自动选最优日期）
    var moodPinnedWeekdaysText: String
    var updatedAt: Date

    init(
        sessionsPerWeek: Int = 4,
        dietAdviceText: String = "",
        weeklySummaryText: String = "",
        lastGeneratedSource: String = "",
        weekStartDate: Date? = nil,
        weeklyBurnGoalKcal: Double = 0,
        excludedExercisesText: String = "",
        dailyCalorieTargetKcal: Double = 0,
        dailyProteinGrams: Double = 0,
        dailyCarbGrams: Double = 0,
        dailyFatGrams: Double = 0,
        nutritionPlanSource: String = "",
        nutritionNotes: String = "",
        restDayCalorieTargetKcal: Double = 0,
        restDayProteinGrams: Double = 0,
        restDayCarbGrams: Double = 0,
        restDayFatGrams: Double = 0,
        restDayNotes: String = "",
        planTypeRaw: String = WorkoutPlanType.balanced.rawValue,
        planStyleRaw: String = WorkoutPlanStyle.professional.rawValue,
        inferredFromHealthKit: Bool = false,
        healthKitWorkoutSummaryText: String = "",
        moodDayOverridesText: String = "",
        moodPinnedWeekdaysText: String = ""
    ) {
        self.id = UUID()
        self.sessionsPerWeek = min(max(sessionsPerWeek, 2), 6)
        self.dietAdviceText = dietAdviceText
        self.weeklySummaryText = weeklySummaryText
        self.lastGeneratedSource = lastGeneratedSource
        self.weekStartDate = weekStartDate
        self.weeklyBurnGoalKcal = weeklyBurnGoalKcal
        self.excludedExercisesText = excludedExercisesText
        self.dailyCalorieTargetKcal = dailyCalorieTargetKcal
        self.dailyProteinGrams = dailyProteinGrams
        self.dailyCarbGrams = dailyCarbGrams
        self.dailyFatGrams = dailyFatGrams
        self.nutritionPlanSource = nutritionPlanSource
        self.nutritionNotes = nutritionNotes
        self.restDayCalorieTargetKcal = restDayCalorieTargetKcal
        self.restDayProteinGrams = restDayProteinGrams
        self.restDayCarbGrams = restDayCarbGrams
        self.restDayFatGrams = restDayFatGrams
        self.restDayNotes = restDayNotes
        self.planTypeRaw = planTypeRaw.isEmpty ? WorkoutPlanType.balanced.rawValue : planTypeRaw
        self.planStyleRaw = planStyleRaw.isEmpty ? WorkoutPlanStyle.professional.rawValue : planStyleRaw
        self.inferredFromHealthKit = inferredFromHealthKit
        self.healthKitWorkoutSummaryText = healthKitWorkoutSummaryText
        self.moodDayOverridesText = moodDayOverridesText
        self.moodPinnedWeekdaysText = moodPinnedWeekdaysText
        self.updatedAt = Date()
    }

    var planType: WorkoutPlanType {
        get { WorkoutPlanType(rawValue: planTypeRaw) ?? .balanced }
        set {
            planTypeRaw = newValue.rawValue
            updatedAt = Date()
        }
    }

    var planStyle: WorkoutPlanStyle {
        get { WorkoutPlanStyle(rawValue: planStyleRaw) ?? .professional }
        set {
            planStyleRaw = newValue.rawValue
            updatedAt = Date()
        }
    }

    var excludedExercises: [String] {
        excludedExercisesText
            .split(separator: "，")
            .flatMap { $0.split(separator: ",") }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    func appendExcludedExercise(_ name: String) {
        var list = excludedExercises
        guard !list.contains(name) else { return }
        list.append(name)
        excludedExercisesText = list.joined(separator: "，")
        updatedAt = Date()
    }
}
