import Foundation
import SwiftData

@Model
final class UserGoal {
    var id: UUID
    var targetWeight: Double          // kg
    var targetDate: Date?             // optional target date
    var targetBodyFat: Double?        // optional target body fat %
    var currentBodyFat: Double?       // manual or HealthKit
    var targetLeanBodyMassKg: Double? // optional target lean mass / muscle (kg)
    var currentLeanBodyMassKg: Double? // manual or HealthKit
    var height: Double                // cm
    var age: Int
    var gender: String                // "male" or "female"
    var activityLevel: String         // "sedentary", "light", "moderate", "active", "very_active"
    var createdAt: Date
    var updatedAt: Date

    init(
        targetWeight: Double,
        height: Double,
        age: Int,
        gender: String,
        activityLevel: String,
        targetDate: Date? = nil,
        targetBodyFat: Double? = nil,
        currentBodyFat: Double? = nil,
        targetLeanBodyMassKg: Double? = nil,
        currentLeanBodyMassKg: Double? = nil
    ) {
        self.id = UUID()
        self.targetWeight = targetWeight
        self.height = height
        self.age = age
        self.gender = gender
        self.activityLevel = activityLevel
        self.targetDate = targetDate
        self.targetBodyFat = targetBodyFat
        self.currentBodyFat = currentBodyFat
        self.targetLeanBodyMassKg = targetLeanBodyMassKg
        self.currentLeanBodyMassKg = currentLeanBodyMassKg
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    // Calculate BMR using Mifflin-St Jeor equation
    func calculateBMR(currentWeight: Double) -> Double {
        if gender == "male" {
            return 10 * currentWeight + 6.25 * height - 5 * Double(age) + 5
        } else {
            return 10 * currentWeight + 6.25 * height - 5 * Double(age) - 161
        }
    }

    /// 注册性别中文标签（供 AI 提示词使用）
    var genderDisplayLabel: String {
        switch gender {
        case "male": return "男"
        case "female": return "女"
        default: return "未设置"
        }
    }

    // Activity multiplier
    var activityMultiplier: Double {
        switch activityLevel {
        case "sedentary": return 1.2
        case "light": return 1.375
        case "moderate": return 1.55
        case "active": return 1.725
        case "very_active": return 1.9
        default: return 1.2
        }
    }

    // Calculate TDEE (Total Daily Energy Expenditure)
    func calculateTDEE(currentWeight: Double) -> Double {
        return calculateBMR(currentWeight: currentWeight) * activityMultiplier
    }

    // Calculate recommended daily calories for weight loss
    // 0.5kg/week loss = 500 kcal deficit per day
    func recommendedDailyCalories(currentWeight: Double) -> Double {
        let tdee = calculateTDEE(currentWeight: currentWeight)
        let weightToLose = currentWeight - targetWeight

        if weightToLose <= 0 {
            // Already at or below target
            return tdee
        }

        // Calculate deficit based on target date or default 0.5kg/week
        var dailyDeficit: Double = 500 // default

        if let targetDate = targetDate {
            let daysRemaining = Calendar.current.dateComponents([.day], from: Date(), to: targetDate).day ?? 1
            if daysRemaining > 0 {
                // 7700 kcal ≈ 1 kg of fat
                dailyDeficit = (weightToLose * 7700) / Double(daysRemaining)
                // Cap at 1000 kcal deficit for safety
                dailyDeficit = min(dailyDeficit, 1000)
            }
        }

        // Minimum 1200 kcal for safety
        return max(tdee - dailyDeficit, 1200)
    }

    /// 由目标体重与目标体脂率推导目标去脂体重（kg）
    var effectiveTargetLeanMassKg: Double? {
        guard let targetBodyFat else { return targetLeanBodyMassKg }
        return targetWeight * (1 - targetBodyFat / 100)
    }

    /// 脂肪量（kg），优先用 HealthKit 体脂率推算
    func fatMassKg(currentWeight: Double) -> Double? {
        guard let bodyFat = currentBodyFat else { return nil }
        return currentWeight * bodyFat / 100
    }

    /// 女生默认目标体重（kg）
    static let femaleDefaultTargetWeightKg = 50.0

    /// 按性别返回默认目标体重（kg）
    static func defaultTargetWeightKg(gender: String) -> Double {
        gender == "female" ? femaleDefaultTargetWeightKg : 65
    }

    /// 将 Apple 健康档案合并进目标（年龄/身高等以健康为准）
    /// @author zhi.qu
    @MainActor
    @discardableResult
    func mergeHealthKitProfile(_ profile: BodyProfileSnapshot, modelContext: ModelContext) -> Bool {
        var changed = false

        if let profileAge = profile.age, (16...100).contains(profileAge), age != profileAge {
            age = profileAge
            changed = true
        }
        if let heightCm = profile.heightCm, heightCm > 50, heightCm < 250, abs(height - heightCm) > 0.5 {
            height = heightCm
            changed = true
        }
        if let profileGender = profile.gender, gender != profileGender {
            gender = profileGender
            changed = true
        }
        if let bodyFat = profile.bodyFatPercent {
            currentBodyFat = bodyFat
            changed = true
        }
        if let lean = profile.leanBodyMassKg, lean > 0 {
            currentLeanBodyMassKg = lean
            changed = true
        }

        if changed {
            updatedAt = Date()
            try? modelContext.save()
        }
        return changed
    }
}
