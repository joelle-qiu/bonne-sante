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

    // MARK: - 阶段二：健康档案

    var healthSummary: HealthProfileEngine.Summary?
    var topFollowUpItem: HealthProfileEngine.AbnormalDisplayItem?
    var activeRiskFlags: [RiskFlag] = []
    var upcomingFitnessTasks: [TodoItem] = []
    var upcomingCheckupPlans: [CheckupPlan] = []
    var nextCheckupDate: Date?

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
        checkupPlans: [CheckupPlan] = []
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

    // MARK: - AI Advisor Context

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
        if let days = cyclePhaseInfo.daysUntilNextPeriod {
            lines.append("距下次经期:\(days)天")
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
