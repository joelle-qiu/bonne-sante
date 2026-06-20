import Foundation

/// 融合 HealthKit 与减脂目标的 TDEE / 热量预算计算（纯函数）
/// @author jiali.qiu
enum IntegratedTDEEEngine {

    struct Input {
        var currentWeight: Double
        var targetWeight: Double
        var targetDate: Date?
        var restingEnergy: Double
        var activeEnergy: Double
        var activityFactor: Double = 1.0
        var bmrFallback: Double?
    }

    struct Output {
        var tdee: Double
        var dailyDeficit: Double
        var dailyBudget: Double
        var proteinGrams: Double
        var fatRatio: Double = 0.28
        var carbCalories: Double
    }

    static func calculate(_ input: Input) -> Output {
        let bmr = input.bmrFallback ?? input.restingEnergy
        let tdee = max(bmr + input.activeEnergy * input.activityFactor, 800)

        let weightToLose = max(input.currentWeight - input.targetWeight, 0)
        var dailyDeficit: Double = 0

        if weightToLose > 0 {
            if let targetDate = input.targetDate {
                let days = max(Calendar.current.dateComponents([.day], from: Date(), to: targetDate).day ?? 1, 1)
                dailyDeficit = min((7700 * weightToLose) / Double(days), 750)
            } else {
                dailyDeficit = 500
            }
        }

        let dailyBudget = max(tdee - dailyDeficit, 1200)
        let proteinGrams = input.currentWeight * 1.6
        let fatCalories = dailyBudget * 0.28
        let proteinCalories = proteinGrams * 4
        let carbCalories = max(dailyBudget - fatCalories - proteinCalories, 0)

        return Output(
            tdee: tdee,
            dailyDeficit: dailyDeficit,
            dailyBudget: dailyBudget,
            proteinGrams: proteinGrams,
            carbCalories: carbCalories
        )
    }

    static func remainingCalories(budget: Double, consumed: Double) -> Double {
        budget - consumed
    }
}
