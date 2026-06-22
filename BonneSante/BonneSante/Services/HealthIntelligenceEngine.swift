import Foundation

/// 聚合 Apple 健康 + 目标 + 体检摘要，生成代谢画像与 AI 个性化上下文
/// @author jiali.qiu
enum HealthIntelligenceEngine {

    struct Profile: Equatable {
        var bmrKcal: Double
        var bmrSource: String
        /// Katch-McArdle 对照值（有体成分时供 UI 展示，不一定作为主 BMR）
        var katchBmrKcal: Double?
        var tdeeKcal: Double
        var tdeeSource: String
        var avgActiveKcal7d: Double?
        var avgBasalKcal7d: Double?
        var basalWatchSampleDays: Int
        var activeWatchSampleDays: Int
        var todayActiveKcal: Double
        var todayBasalKcal: Double
        var avgSteps7d: Int?
        var bodyFatPercent: Double?
        var leanBodyMassKg: Double?
        var fatMassKg: Double?
        var weightTrendKgPerWeek: Double?
        var selfReportedActivity: String
        var calibratedActivity: String
        var proteinGramsSuggested: Double

        /// 首页/设置页短标签
        var bmrSourceShort: String {
            switch bmrSource {
            case let s where s.contains("近7日"): return "Watch 7日均值"
            case let s where s.contains("Katch"): return "PICOOC 去脂体重"
            case let s where s.contains("今日"): return "Watch 今日"
            default: return "公式估算"
            }
        }

        var tdeeSourceShort: String {
            switch tdeeSource {
            case let s where s.contains("近7日"): return "Watch 7日均值"
            case let s where s.contains("今日"): return "Watch 今日"
            case let s where s.contains("去脂体重"): return "体成分+活动估算"
            default: return "公式估算"
            }
        }
    }

    /// 构建代谢与体成分画像（供 TDEE 与 AI 共用）
    static func buildProfile(
        goal: UserGoal,
        currentWeight: Double,
        bodyProfile: BodyProfileSnapshot,
        energyProfile: EnergyProfileSnapshot,
        weightHistory: [WeightRecord],
        workoutsPerWeekEstimate: Double = 0
    ) -> Profile {
        let bmrMifflin = goal.calculateBMR(currentWeight: currentWeight)
        let bmrKatch = bodyProfile.leanBodyMassKg.map { 370 + 21.6 * $0 }

        let (bmr, bmrSource) = selectBMR(
            katch: bmrKatch,
            avgBasal7d: energyProfile.avgBasalKcal7d,
            basalSampleDays: energyProfile.basalSampleDays7d,
            todayBasal: energyProfile.todayBasalKcal,
            mifflin: bmrMifflin,
            hasWatchData: energyProfile.hasWatchData
        )

        let estimatedActiveFromGoal = max(goal.calculateTDEE(currentWeight: currentWeight) - bmrMifflin, 0)
        let activeForTdee = energyProfile.avgActiveKcal7d
            ?? (energyProfile.hasWatchData ? energyProfile.todayActiveKcal : nil)
            ?? estimatedActiveFromGoal

        let tdee = max(bmr + activeForTdee, 800)
        let tdeeSource: String
        if energyProfile.avgActiveKcal7d != nil, energyProfile.avgBasalKcal7d != nil {
            tdeeSource = "Apple 健康近7日基础+活动均值"
        } else if energyProfile.hasWatchData {
            tdeeSource = "Apple Watch 今日基础+活动"
        } else if bodyProfile.leanBodyMassKg != nil {
            tdeeSource = "去脂体重 BMR + 活动估算"
        } else {
            tdeeSource = "Mifflin-St Jeor + 自报活动量"
        }

        let calibrated = calibrateActivityLevel(
            selfReported: goal.activityLevel,
            avgActiveKcal7d: energyProfile.avgActiveKcal7d,
            workoutsPerWeek: workoutsPerWeekEstimate
        )

        let protein = suggestedProtein(
            weightKg: currentWeight,
            leanMassKg: bodyProfile.leanBodyMassKg
        )

        let fatMass: Double?
        if let weight = bodyProfile.currentWeightKg ?? Optional(currentWeight),
           let bf = bodyProfile.bodyFatPercent {
            fatMass = weight * bf / 100
        } else {
            fatMass = bodyProfile.fatMassKg
        }

        return Profile(
            bmrKcal: bmr,
            bmrSource: bmrSource,
            katchBmrKcal: bmrKatch,
            tdeeKcal: tdee,
            tdeeSource: tdeeSource,
            avgActiveKcal7d: energyProfile.avgActiveKcal7d,
            avgBasalKcal7d: energyProfile.avgBasalKcal7d,
            basalWatchSampleDays: energyProfile.basalSampleDays7d,
            activeWatchSampleDays: energyProfile.activeSampleDays7d,
            todayActiveKcal: energyProfile.todayActiveKcal,
            todayBasalKcal: energyProfile.todayBasalKcal,
            avgSteps7d: energyProfile.avgSteps7d,
            bodyFatPercent: bodyProfile.bodyFatPercent,
            leanBodyMassKg: bodyProfile.leanBodyMassKg,
            fatMassKg: fatMass,
            weightTrendKgPerWeek: weightTrendKgPerWeek(from: weightHistory),
            selfReportedActivity: goal.activityLevel,
            calibratedActivity: calibrated,
            proteinGramsSuggested: protein
        )
    }

    /// 供 AI 训练计划使用的个性化上下文（代谢 + 体成分 + 体检饮食建议）
    static func formatForWorkoutAI(
        profile: Profile,
        healthSummary: HealthProfileEngine.Summary?,
        habitSummary: String,
        targetBodyFat: Double?,
        targetLeanMassKg: Double?
    ) -> String {
        var lines: [String] = []

        lines.append("【代谢画像（请据此定制消耗与营养）】")
        lines.append("基础代谢 BMR：\(Int(profile.bmrKcal)) kcal/天（\(profile.bmrSource)）")
        if let katch = profile.katchBmrKcal, profile.bmrSource.contains("近7日") {
            let delta = Int(katch - profile.bmrKcal)
            lines.append("体成分对照 BMR（PICOOC）：\(Int(katch)) kcal/天（与 Watch 差 \(delta >= 0 ? "+" : "")\(delta)）")
        }
        lines.append("日均总消耗 TDEE：\(Int(profile.tdeeKcal)) kcal/天（\(profile.tdeeSource)）")
        if let avgA = profile.avgActiveKcal7d {
            lines.append("近7日平均活动消耗：\(Int(avgA)) kcal/天")
        }
        if let avgB = profile.avgBasalKcal7d {
            lines.append("近7日平均基础消耗：\(Int(avgB)) kcal/天")
        }
        if profile.avgActiveKcal7d == nil, profile.hasWatchDataToday {
            lines.append("今日 Watch 活动：\(Int(profile.todayActiveKcal)) kcal · 基础：\(Int(profile.todayBasalKcal)) kcal")
        }
        if let steps = profile.avgSteps7d {
            lines.append("近7日平均步数：\(steps) 步/天")
        }
        lines.append("活动水平：自报「\(activityLabel(profile.selfReportedActivity))」→ 校准「\(activityLabel(profile.calibratedActivity))」（请按校准水平安排强度）")
        lines.append("建议蛋白质：\(Int(profile.proteinGramsSuggested)) g/天（含 lean mass 优先）")

        if profile.bodyFatPercent != nil || profile.leanBodyMassKg != nil {
            lines.append("")
            lines.append("【体成分】")
            if let bf = profile.bodyFatPercent {
                lines.append("体脂率：\(String(format: "%.1f", bf))%")
            }
            if let fat = profile.fatMassKg {
                lines.append("脂肪量：约 \(String(format: "%.1f", fat)) kg")
            }
            if let lean = profile.leanBodyMassKg {
                lines.append("去脂体重/肌肉：\(String(format: "%.1f", lean)) kg")
            }
            if let target = targetBodyFat {
                lines.append("目标体脂：\(String(format: "%.1f", target))%")
            }
            if let target = targetLeanMassKg {
                lines.append("目标去脂体重：\(String(format: "%.1f", target)) kg")
            }
        }

        if let trend = profile.weightTrendKgPerWeek {
            let dir = trend < -0.05 ? "下降" : (trend > 0.05 ? "上升" : "平稳")
            lines.append("体重趋势（近记录）：\(dir)约 \(String(format: "%.2f", abs(trend))) kg/周")
        }

        if !habitSummary.isEmpty {
            lines.append("")
            lines.append("【锻炼习惯】")
            lines.append(habitSummary)
        }

        if let summary = healthSummary {
            if !summary.dietaryNotes.isEmpty {
                lines.append("")
                lines.append("【体检/档案饮食约束（必须遵守）】")
                for note in summary.dietaryNotes.prefix(6) {
                    lines.append("· \(note)")
                }
            }
            if let floor = summary.proteinFloorGrams {
                lines.append("体检建议蛋白下限：\(String(format: "%.1f", floor)) g/kg 体重")
            }
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - Private

    private static func selectBMR(
        katch: Double?,
        avgBasal7d: Double?,
        basalSampleDays: Int,
        todayBasal: Double,
        mifflin: Double,
        hasWatchData: Bool
    ) -> (Double, String) {
        // 每日佩戴 Watch 时，近7日均值最贴近真实个体 BMR
        if let avgBasal7d, avgBasal7d > 800, basalSampleDays >= 3 {
            return (avgBasal7d, "Apple 健康近7日基础代谢均值")
        }
        // 无稳定 Watch 数据时，PICOOC 等体脂秤同步的去脂体重更准于纯公式
        if let katch, katch > 800 {
            return (katch, "Katch-McArdle（PICOOC 去脂体重）")
        }
        if hasWatchData, todayBasal > 800 {
            return (todayBasal, "Apple Watch 今日基础代谢")
        }
        return (mifflin, "Mifflin-St Jeor 公式")
    }

    private static func suggestedProtein(weightKg: Double, leanMassKg: Double?) -> Double {
        let byWeight = weightKg * 1.6
        if let lean = leanMassKg, lean > 0 {
            return max(byWeight, lean * 2.0)
        }
        return byWeight
    }

    private static func calibrateActivityLevel(
        selfReported: String,
        avgActiveKcal7d: Double?,
        workoutsPerWeek: Double
    ) -> String {
        if let avg = avgActiveKcal7d {
            if avg >= 550 || workoutsPerWeek >= 5.5 { return "very_active" }
            if avg >= 400 || workoutsPerWeek >= 4.5 { return "active" }
            if avg >= 250 || workoutsPerWeek >= 3 { return "moderate" }
            if avg >= 120 || workoutsPerWeek >= 1.5 { return "light" }
            return "sedentary"
        }
        if workoutsPerWeek >= 5 { return "active" }
        if workoutsPerWeek >= 3 { return "moderate" }
        return selfReported
    }

    private static func weightTrendKgPerWeek(from records: [WeightRecord]) -> Double? {
        let sorted = records.sorted { $0.date < $1.date }
        guard sorted.count >= 2,
              let first = sorted.first,
              let last = sorted.last else { return nil }
        let days = max(Calendar.current.dateComponents([.day], from: first.date, to: last.date).day ?? 1, 1)
        return (last.weight - first.weight) / Double(days) * 7
    }

    private static func activityLabel(_ raw: String) -> String {
        switch raw {
        case "sedentary": return "久坐"
        case "light": return "轻度"
        case "moderate": return "中度"
        case "active": return "活跃"
        case "very_active": return "非常活跃"
        default: return raw
        }
    }
}

private extension HealthIntelligenceEngine.Profile {
    var hasWatchDataToday: Bool {
        todayActiveKcal > 0 || todayBasalKcal > 0
    }
}
