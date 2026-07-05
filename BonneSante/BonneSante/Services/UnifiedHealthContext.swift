import Foundation
import SwiftData
import SwiftUI

/// 统一健康上下文 — 全 App 单一真相源
/// @author jiali.qiu
@Observable
@MainActor
final class UnifiedHealthContext {
    // MARK: - Published State

    var caloriesConsumed: Double = 0
    var caloriesBurned: Double = 0
    var dailyCalorieBudget: Double?
    var remainingCalories: Double?
    var dailyDeficit: Double = 0
    /// 减脂计划宏量目标（来自 IntegratedTDEEEngine）
    var macroTargets: MacroTargets?
    var currentWeight: Double?
    var userGoal: UserGoal?
    var cyclePhaseInfo: CycleEngine.PhaseInfo = CycleEngine.phaseInfo(from: nil)
    var aiStatus: AIServiceStatus = .current
    var isUsingWatchData: Bool = false
    var lastRefreshedAt: Date?
    /// 当前生效的营养目标来源：ai | engine | nil
    var nutritionPlanSource: String?
    /// 今日是否为训练日（有排课则 true）
    var isTrainingDayToday: Bool = false
    /// 未叠加训练计划前的减脂基准（用于展示「微调」）
    var baselineDailyBudget: Double?
    var baselineMacroTargets: MacroTargets?
    /// 今日目标相对减脂建议的微调说明
    var nutritionAdjustmentNote: String?

    /// refresh 时缓存，供 AI 教练读取近 30 日趋势
    private(set) var cachedWeightEntries: [WeightEntry] = []
    private(set) var cachedFoodEntries: [FoodEntry] = []

    // MARK: - 阶段二：健康档案

    var healthSummary: HealthProfileEngine.Summary?
    var topFollowUpItem: HealthProfileEngine.AbnormalDisplayItem?
    var activeRiskFlags: [RiskFlag] = []
    var upcomingFitnessTasks: [TodoItem] = []
    var upcomingCheckupPlans: [CheckupPlan] = []
    var nextCheckupDate: Date?

    /// 每日宏量营养素目标
    struct MacroTargets: Equatable {
        var proteinGrams: Double
        var carbGrams: Double
        var fatGrams: Double
    }

    /// 代谢与体成分画像（HealthKit + 目标融合）
    var intelligenceProfile: HealthIntelligenceEngine.Profile?

    // MARK: - Dependencies

    let healthKitService: HealthKitService

    init(healthKitService: HealthKitService) {
        self.healthKitService = healthKitService
    }

    convenience init() {
        self.init(healthKitService: HealthKitService())
    }

    // MARK: - Refresh

    func refresh(
        foodEntries: [FoodEntry],
        goals: [UserGoal],
        weightEntries: [WeightEntry],
        cycleProfiles: [CycleProfile],
        reports: [Report] = [],
        riskFlags: [RiskFlag] = [],
        todos: [TodoItem] = [],
        checkupPlans: [CheckupPlan] = [],
        workoutPreferences: WorkoutPlanPreferences? = nil,
        isTrainingDayToday: Bool = false
    ) async {
        self.isTrainingDayToday = isTrainingDayToday
        aiStatus = .current
        userGoal = goals.first
        cachedWeightEntries = weightEntries
        cachedFoodEntries = foodEntries

        let startOfDay = Calendar.current.startOfDay(for: Date())
        let todayFood = foodEntries.filter { $0.createdAt >= startOfDay }
        caloriesConsumed = todayFood.reduce(0) { $0 + $1.calories }

        await healthKitService.fetchTodayCaloriesBurned()
        await healthKitService.fetchRecentWorkouts(days: 30)
        await healthKitService.fetchEnergyProfile()
        await healthKitService.fetchDailyEnergyTrend(days: 30)
        await healthKitService.fetchBodyProfile()

        let manualWeight = weightEntries.first?.weight
        currentWeight = healthKitService.currentWeight ?? manualWeight

        isUsingWatchData = healthKitService.energyProfile.hasWatchData

        applyTDEEAndNutritionOverlay(
            goals: goals,
            workoutPreferences: workoutPreferences,
            isTrainingDayToday: isTrainingDayToday
        )

        await healthKitService.fetchMenstrualCycleSnapshot()
        cyclePhaseInfo = CycleEngine.phaseInfo(
            from: cycleProfiles.first,
            healthKit: healthKitService.menstrualSnapshot
        )

        let verifiedMetrics = reports.filter(\.isVerified).flatMap(\.metrics)
        let ruleMatches = ClinicalRiskEngine.analyze(metrics: verifiedMetrics)
        healthSummary = HealthProfileEngine.buildSummary(
            from: verifiedMetrics,
            risks: ruleMatches
        )

        topFollowUpItem = HealthProfileEngine.topPriorityFollowUp(from: healthSummary)
        activeRiskFlags = riskFlags
            .filter { !$0.isResolved }
            .sorted { lhs, rhs in
                let order: [RiskSeverity] = [.high, .medium, .low]
                let li = order.firstIndex(of: lhs.severityLevel) ?? order.count
                let ri = order.firstIndex(of: rhs.severityLevel) ?? order.count
                if li != ri { return li < ri }
                return lhs.createdDate > rhs.createdDate
            }
        upcomingFitnessTasks = todos
            .filter { !$0.isCompleted && $0.sourceType.isFitnessTask }
            .sorted { $0.dueDate < $1.dueDate }
        upcomingCheckupPlans = checkupPlans.sorted { $0.nextDueDate < $1.nextDueDate }
        nextCheckupDate = upcomingCheckupPlans.map(\.nextDueDate).filter { $0 > Date() }.min()

        lastRefreshedAt = Date()
    }

    /// 轻量刷新：仅更新能量/营养/周期（训练计划页用，避免重复跑健康档案分析）
    func refreshNutritionAndEnergy(
        foodEntries: [FoodEntry],
        goals: [UserGoal],
        weightEntries: [WeightEntry],
        cycleProfiles: [CycleProfile],
        workoutPreferences: WorkoutPlanPreferences? = nil,
        isTrainingDayToday: Bool = false
    ) async {
        self.isTrainingDayToday = isTrainingDayToday
        userGoal = goals.first

        let startOfDay = Calendar.current.startOfDay(for: Date())
        let todayFood = foodEntries.filter { $0.createdAt >= startOfDay }
        caloriesConsumed = todayFood.reduce(0) { $0 + $1.calories }

        await healthKitService.fetchTodayCaloriesBurned()
        await healthKitService.fetchEnergyProfile()
        await healthKitService.fetchBodyProfile()
        await healthKitService.fetchRecentWorkouts()

        let manualWeight = weightEntries.first?.weight
        currentWeight = healthKitService.currentWeight ?? manualWeight
        isUsingWatchData = healthKitService.energyProfile.hasWatchData

        applyTDEEAndNutritionOverlay(
            goals: goals,
            workoutPreferences: workoutPreferences,
            isTrainingDayToday: isTrainingDayToday
        )

        cyclePhaseInfo = CycleEngine.phaseInfo(
            from: cycleProfiles.first,
            healthKit: healthKitService.menstrualSnapshot
        )
        lastRefreshedAt = Date()
    }

    /// 训练详情页：仅刷新 HealthKit 活动/锻炼（不跑完整 refresh）
    func refreshHealthKitOnly() async {
        await healthKitService.fetchTodayCaloriesBurned()
        await healthKitService.fetchEnergyProfile()
        await healthKitService.fetchRecentWorkouts()
        isUsingWatchData = healthKitService.energyProfile.hasWatchData
    }

    /// TDEE 基准 + 训练计划营养微调叠加
    private func applyTDEEAndNutritionOverlay(
        goals: [UserGoal],
        workoutPreferences: WorkoutPlanPreferences?,
        isTrainingDayToday: Bool
    ) {
        nutritionAdjustmentNote = nil
        intelligenceProfile = nil

        if let goal = userGoal, let weight = currentWeight {
            let workoutsPerWeek = Double(healthKitService.recentWorkouts.count)
            let intel = HealthIntelligenceEngine.buildProfile(
                goal: goal,
                currentWeight: weight,
                bodyProfile: healthKitService.bodyProfile,
                energyProfile: healthKitService.energyProfile,
                weightHistory: healthKitService.weightHistory,
                workoutsPerWeekEstimate: workoutsPerWeek > 0 ? workoutsPerWeek : Double(workoutPreferences?.sessionsPerWeek ?? 0)
            )
            intelligenceProfile = intel

            let output = IntegratedTDEEEngine.calculate(
                IntegratedTDEEEngine.Input(
                    currentWeight: weight,
                    targetWeight: goal.targetWeight,
                    targetDate: goal.targetDate,
                    restingEnergy: intel.bmrKcal,
                    activeEnergy: intel.tdeeKcal - intel.bmrKcal,
                    bmrFallback: intel.bmrKcal,
                    leanBodyMassKg: intel.leanBodyMassKg,
                    proteinGramsOverride: intel.proteinGramsSuggested
                )
            )

            dailyCalorieBudget = output.dailyBudget
            dailyDeficit = output.dailyDeficit
            macroTargets = MacroTargets(
                proteinGrams: output.proteinGrams,
                carbGrams: output.carbGrams,
                fatGrams: output.fatGrams
            )
            baselineDailyBudget = output.dailyBudget
            baselineMacroTargets = macroTargets
            caloriesBurned = intel.tdeeKcal
            remainingCalories = IntegratedTDEEEngine.remainingCalories(
                budget: output.dailyBudget,
                consumed: caloriesConsumed
            )
        } else {
            caloriesBurned = healthKitService.totalCaloriesBurned
            dailyCalorieBudget = nil
            remainingCalories = nil
            macroTargets = nil
            baselineDailyBudget = nil
            baselineMacroTargets = nil
        }

        if WorkoutNutritionPlanner.hasActivePlan(workoutPreferences),
           let prefs = workoutPreferences {
            nutritionPlanSource = prefs.nutritionPlanSource
            let effective = WorkoutNutritionPlanner.effectivePlan(prefs, isTrainingDay: isTrainingDayToday)
            macroTargets = MacroTargets(
                proteinGrams: effective.proteinGrams,
                carbGrams: effective.carbGrams,
                fatGrams: effective.fatGrams
            )
            if effective.caloriesKcal > 0 {
                dailyCalorieBudget = effective.caloriesKcal
                remainingCalories = IntegratedTDEEEngine.remainingCalories(
                    budget: effective.caloriesKcal,
                    consumed: caloriesConsumed
                )
            }
            nutritionAdjustmentNote = WorkoutNutritionPlanner.todayNutritionSubtitle(
                source: prefs.nutritionPlanSource,
                isTrainingDay: isTrainingDayToday,
                effectiveCalories: effective.caloriesKcal,
                baselineCalories: baselineDailyBudget
            )
        } else {
            nutritionPlanSource = nil
        }
    }

    // MARK: - AI Advisor Context

    func advisorContextSummary() -> String {
        var lines: [String] = []

        if let budget = dailyCalorieBudget {
            lines.append("今日热量预算:\(Int(budget))kcal")
        }
        lines.append("今日已摄入:\(Int(caloriesConsumed))kcal")
        if let remaining = remainingCalories {
            lines.append("今日剩余可摄入:\(Int(remaining))kcal")
        }
        if dailyDeficit > 0 {
            lines.append("计划热量缺口:\(Int(dailyDeficit))kcal/天")
        }
        if let weight = currentWeight {
            lines.append("当前体重:\(String(format: "%.1f", weight))kg")
        }
        let energy = healthKitService.energyProfile
        if healthKitService.activeCaloriesBurned > 0 {
            lines.append("今日活动消耗(含走路等):\(Int(healthKitService.activeCaloriesBurned))kcal")
        }
        let todayWorkout = WorkoutEnergyCalculator.workoutBurn(
            on: Date(),
            from: healthKitService.recentWorkouts
        )
        if todayWorkout > 0 {
            lines.append("今日锻炼消耗(Workout记录):\(Int(todayWorkout))kcal")
        }
        if healthKitService.basalCaloriesBurned > 0 {
            lines.append("今日基础代谢:\(Int(healthKitService.basalCaloriesBurned))kcal")
        }
        if energy.todayActiveKcal > 0 || energy.todayBasalKcal > 0 {
            lines.append("今日总消耗(基础+活动):\(Int(energy.todayBasalKcal + energy.todayActiveKcal))kcal")
        }
        if energy.weekActiveKcal > 0 {
            lines.append("本周累计活动:\(Int(energy.weekActiveKcal))kcal")
        }
        if caloriesBurned > 0 {
            lines.append("日均总消耗(TDEE):\(Int(caloriesBurned))kcal")
        }
        if let intel = intelligenceProfile {
            lines.append("基础代谢(BMR):\(Int(intel.bmrKcal))kcal(\(intel.bmrSource))")
            lines.append("TDEE来源:\(intel.tdeeSource)")
            if let steps = intel.avgSteps7d {
                lines.append("近7日平均步数:\(steps)步/天")
            }
            if let bf = intel.bodyFatPercent {
                lines.append("体脂率:\(String(format: "%.1f", bf))%")
            }
            if let lean = intel.leanBodyMassKg {
                lines.append("去脂体重:\(String(format: "%.1f", lean))kg")
            }
        }
        lines.append("生理周期:\(cyclePhaseInfo.label)")
        lines.append("周期建议:\(cyclePhaseInfo.tip)")
        if let days = cyclePhaseInfo.daysUntilNextPeriod {
            lines.append("距下次经期:\(days)天")
        }

        if let targets = macroTargets, nutritionPlanSource != nil {
            let dayLabel = WorkoutNutritionPlanner.dayTypeLabel(isTrainingDay: isTrainingDayToday)
            lines.append("营养目标(\(dayLabel)·\(WorkoutNutritionPlanner.planSourceLabel(nutritionPlanSource ?? ""))): 蛋白\(Int(targets.proteinGrams))g 碳水\(Int(targets.carbGrams))g 脂肪\(Int(targets.fatGrams))g")
        }

        if let summary = healthSummary, summary.activeRiskCount > 0 {
            lines.append("健康摘要:\(summary.headline)")
            for note in summary.dietaryNotes {
                lines.append("饮食注意:\(note)")
            }
            if let protein = summary.proteinFloorGrams, let weight = currentWeight {
                lines.append("蛋白质建议下限:\(Int(protein * weight))g/天")
            }
            for risk in activeRiskFlags.prefix(3) {
                lines.append("风险提醒:\(risk.metricName) \(risk.currentValue) — \(risk.suggestedAction)")
            }
        }

        appendMonthlyTrends(to: &lines)

        return lines.joined(separator: "\n")
    }

    /// 近 30 日体重、锻炼与活动消耗趋势（AI 教练专用）
    private func appendMonthlyTrends(to lines: inout [String]) {
        let calendar = Calendar.current
        let cutoff = calendar.date(byAdding: .day, value: -30, to: Date()) ?? Date()
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M/d"

        // 体重：合并 SwiftData 手动记录 + HealthKit
        var weightByDay: [Date: (weight: Double, source: String)] = [:]
        for record in healthKitService.dailyWeights where record.date >= cutoff {
            let day = calendar.startOfDay(for: record.date)
            weightByDay[day] = (record.weight, "healthkit")
        }
        for entry in cachedWeightEntries where entry.date >= cutoff {
            let day = calendar.startOfDay(for: entry.date)
            weightByDay[day] = (entry.weight, entry.source)
        }
        if !weightByDay.isEmpty {
            let sorted = weightByDay.sorted { $0.key < $1.key }
            let trend = sorted.map { "\(formatter.string(from: $0.key)):\(String(format: "%.1f", $0.value.weight))kg" }
                .joined(separator: " ")
            lines.append("近30天体重(\(sorted.count)次):\(trend)")
            if let first = sorted.first, let last = sorted.last, sorted.count >= 2 {
                let delta = last.value.weight - first.value.weight
                lines.append("30天体重变化:\(String(format: "%+.1f", delta))kg")
            }
        }

        // 锻炼消耗趋势
        let trend = healthKitService.dailyEnergyTrend.filter { $0.date >= cutoff }
        if !trend.isEmpty {
            let workoutDays = trend.filter { $0.workoutKcal > 0 }
            let totalWorkout = workoutDays.reduce(0) { $0 + $1.workoutKcal }
            let avgWorkout = totalWorkout / Double(max(workoutDays.count, 1))
            lines.append("近30天锻炼:\(workoutDays.count)天有记录,累计\(Int(totalWorkout))kcal,均\(Int(avgWorkout))kcal/练日")

            let recentWorkoutLine = workoutDays.suffix(8).map {
                "\(formatter.string(from: $0.date)):\(Int($0.workoutKcal))"
            }.joined(separator: " ")
            if !recentWorkoutLine.isEmpty {
                lines.append("近期锻炼kcal:\(recentWorkoutLine)")
            }

            let activeDays = trend.filter { $0.activeKcal > 0 }
            if !activeDays.isEmpty {
                let avgActive = activeDays.reduce(0) { $0 + $1.activeKcal } / Double(activeDays.count)
                lines.append("近30天日均活动消耗:\(Int(avgActive))kcal(\(activeDays.count)天有数据)")
            }
        }

        // 摄入趋势（SwiftData 饮食日记）
        var intakeByDay: [Date: Double] = [:]
        for entry in cachedFoodEntries where entry.createdAt >= cutoff {
            let day = calendar.startOfDay(for: entry.createdAt)
            intakeByDay[day, default: 0] += entry.calories
        }
        if !intakeByDay.isEmpty {
            let values = intakeByDay.values
            let avgIntake = values.reduce(0, +) / Double(values.count)
            lines.append("近30天日均摄入:\(Int(avgIntake))kcal(\(intakeByDay.count)天有记录)")
            let recentIntake = intakeByDay.sorted { $0.key < $1.key }.suffix(7).map {
                "\(formatter.string(from: $0.key)):\(Int($0.value))"
            }.joined(separator: " ")
            lines.append("近7天摄入kcal:\(recentIntake)")
        }

        if healthKitService.energyProfile.weekWorkoutKcal > 0 {
            lines.append("本周锻炼消耗:\(Int(healthKitService.energyProfile.weekWorkoutKcal))kcal(不含日常活动)")
        }
    }
}

private struct UnifiedHealthContextKey: EnvironmentKey {
    static let defaultValue: UnifiedHealthContext? = nil
}

extension EnvironmentValues {
    var healthContext: UnifiedHealthContext? {
        get { self[UnifiedHealthContextKey.self] }
        set { self[UnifiedHealthContextKey.self] = newValue }
    }
}

extension View {
    func healthContext(_ context: UnifiedHealthContext) -> some View {
        environment(\.healthContext, context)
    }
}
