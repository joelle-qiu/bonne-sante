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
        /// 去脂体重（kg），有则优先 Katch-McArdle 蛋白计算
        var leanBodyMassKg: Double?
        /// 建议蛋白（已由 HealthIntelligenceEngine 校准时可传入）
        var proteinGramsOverride: Double?
    }

    struct Output {
        var tdee: Double
        var dailyDeficit: Double
        var dailyBudget: Double
        var proteinGrams: Double
        var fatRatio: Double = 0.28
        var carbCalories: Double
        /// 脂肪目标克数（dailyBudget × fatRatio ÷ 9）
        var fatGrams: Double
        /// 碳水目标克数（剩余热量 ÷ 4）
        var carbGrams: Double
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
        let proteinGrams = input.proteinGramsOverride ?? proteinFromBody(
            weightKg: input.currentWeight,
            leanMassKg: input.leanBodyMassKg
        )
        let fatRatio = 0.28
        let fatCalories = dailyBudget * fatRatio
        let proteinCalories = proteinGrams * 4
        let carbCalories = max(dailyBudget - fatCalories - proteinCalories, 0)
        let fatGrams = fatCalories / 9
        let carbGrams = carbCalories / 4

        return Output(
            tdee: tdee,
            dailyDeficit: dailyDeficit,
            dailyBudget: dailyBudget,
            proteinGrams: proteinGrams,
            fatRatio: fatRatio,
            carbCalories: carbCalories,
            fatGrams: fatGrams,
            carbGrams: carbGrams
        )
    }

    static func remainingCalories(budget: Double, consumed: Double) -> Double {
        budget - consumed
    }

    private static func proteinFromBody(weightKg: Double, leanMassKg: Double?) -> Double {
        let byWeight = weightKg * 1.6
        if let lean = leanMassKg, lean > 0 {
            return max(byWeight, lean * 2.0)
        }
        return byWeight
    }
}
