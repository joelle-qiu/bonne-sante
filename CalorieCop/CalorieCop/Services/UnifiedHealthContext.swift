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
    var currentWeight: Double?
    var userGoal: UserGoal?
    var cyclePhaseInfo: CycleEngine.PhaseInfo = CycleEngine.phaseInfo(from: nil)
    var aiStatus: AIServiceStatus = .current
    var isUsingWatchData: Bool = false
    var lastRefreshedAt: Date?

    // MARK: - Dependencies

    let healthKitService: HealthKitService

    init(healthKitService: HealthKitService = HealthKitService()) {
        self.healthKitService = healthKitService
    }

    // MARK: - Refresh

    func refresh(
        foodEntries: [FoodEntry],
        goals: [UserGoal],
        weightEntries: [WeightEntry],
        cycleProfiles: [CycleProfile]
    ) async {
        aiStatus = .current
        userGoal = goals.first

        let startOfDay = Calendar.current.startOfDay(for: Date())
        let todayFood = foodEntries.filter { $0.createdAt >= startOfDay }
        caloriesConsumed = todayFood.reduce(0) { $0 + $1.calories }

        await healthKitService.fetchTodayCaloriesBurned()

        let manualWeight = weightEntries.first?.weight
        currentWeight = healthKitService.currentWeight ?? manualWeight

        isUsingWatchData = healthKitService.totalCaloriesBurned > 0

        if let goal = userGoal, let weight = currentWeight {
            let bmr = goal.calculateBMR(currentWeight: weight)
            let resting = isUsingWatchData ? healthKitService.basalCaloriesBurned : bmr
            let active = isUsingWatchData ? healthKitService.activeCaloriesBurned : (goal.calculateTDEE(currentWeight: weight) - bmr)

            let output = IntegratedTDEEEngine.calculate(
                IntegratedTDEEEngine.Input(
                    currentWeight: weight,
                    targetWeight: goal.targetWeight,
                    targetDate: goal.targetDate,
                    restingEnergy: resting,
                    activeEnergy: active,
                    bmrFallback: bmr
                )
            )

            dailyCalorieBudget = output.dailyBudget
            dailyDeficit = output.dailyDeficit
            caloriesBurned = output.tdee
            remainingCalories = IntegratedTDEEEngine.remainingCalories(
                budget: output.dailyBudget,
                consumed: caloriesConsumed
            )
        } else {
            caloriesBurned = healthKitService.totalCaloriesBurned
            dailyCalorieBudget = nil
            remainingCalories = nil
        }

        cyclePhaseInfo = CycleEngine.phaseInfo(from: cycleProfiles.first)
        lastRefreshedAt = Date()
    }

    // MARK: - AI Advisor Context

    /// 为 AI 顾问 Prompt 生成今日健康摘要
    func advisorContextSummary() -> String {
        var lines: [String] = []

        if let budget = dailyCalorieBudget {
            lines.append("今日热量预算:\(Int(budget))kcal")
        }
        lines.append("今日已摄入:\(Int(caloriesConsumed))kcal")
        if let remaining = remainingCalories {
            lines.append("今日剩余:\(Int(remaining))kcal")
        }
        if caloriesBurned > 0 {
            lines.append("今日消耗(TDEE):\(Int(caloriesBurned))kcal")
        }
        lines.append("生理周期:\(cyclePhaseInfo.label)")
        lines.append("周期建议:\(cyclePhaseInfo.tip)")

        return lines.joined(separator: "\n")
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
