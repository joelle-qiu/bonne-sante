import Foundation

/// 根据 Apple 健康锻炼历史推断训练计划偏好（计划类型、每周频率）
/// @author jiali.qiu
enum WorkoutPreferenceInferencer {

    /// 推断结果
    struct Result: Equatable {
        var planType: WorkoutPlanType
        var sessionsPerWeek: Int
        /// 写入偏好并注入 AI 提示词的摘要
        var summaryText: String
        var hadEnoughData: Bool
    }

    private static let strengthLabels: Set<String> = ["力量训练"]
    private static let cardioLabels: Set<String> = ["跑步", "步行", "骑行", "游泳", "椭圆机", "徒步"]
    private static let hiitLabels: Set<String> = ["HIIT"]
    private static let mindBodyLabels: Set<String> = ["瑜伽", "普拉提"]

    /// 分析近 90 天锻炼记录，推荐 planType 与 sessionsPerWeek
    static func infer(
        from workouts: [WorkoutSnapshot],
        lookbackDays: Int = 90,
        referenceDate: Date = Date()
    ) -> Result {
        let calendar = Calendar.current
        let start = calendar.date(byAdding: .day, value: -lookbackDays, to: referenceDate) ?? referenceDate
        let inRange = workouts.filter { $0.date >= start && $0.date <= referenceDate }

        guard !inRange.isEmpty else {
            return Result(
                planType: .balanced,
                sessionsPerWeek: 4,
                summaryText: "近 \(lookbackDays) 天暂无 Apple 健康锻炼记录，已使用默认偏好（智能均衡 · 4 次/周）。",
                hadEnoughData: false
            )
        }

        let totalSessions = inRange.count
        let totalMinutes = inRange.reduce(0) { $0 + $1.durationMinutes }
        let avgMinutes = totalMinutes / Double(totalSessions)

        let strengthMinutes = minutes(in: inRange, labels: strengthLabels)
        let cardioMinutes = minutes(in: inRange, labels: cardioLabels.union(hiitLabels))
        let mindBodyMinutes = minutes(in: inRange, labels: mindBodyLabels)
        let otherMinutes = max(totalMinutes - strengthMinutes - cardioMinutes - mindBodyMinutes, 0)

        let strengthShare = totalMinutes > 0 ? strengthMinutes / totalMinutes : 0
        let cardioShare = totalMinutes > 0 ? cardioMinutes / totalMinutes : 0

        let sessionsPerWeek = averageSessionsPerWeek(workouts: inRange, referenceDate: referenceDate, calendar: calendar)
        let planType = recommendPlanType(
            strengthShare: strengthShare,
            cardioShare: cardioShare,
            sessionsPerWeek: sessionsPerWeek
        )

        let breakdown = activityBreakdown(in: inRange, totalMinutes: totalMinutes)
        let hadEnoughData = totalSessions >= 4

        var summary = "近 \(lookbackDays) 天 Apple 健康锻炼：共 \(totalSessions) 次，约每周 \(String(format: "%.1f", Double(sessionsPerWeek))) 次，均场 \(Int(avgMinutes)) 分钟。"
        if !breakdown.isEmpty {
            summary += "\n类型占比：" + breakdown.joined(separator: "、")
        }
        if hadEnoughData {
            summary += "\n已推荐：\(planType.label) · \(sessionsPerWeek) 次/周。"
        } else {
            summary += "\n记录较少，计划类型保持智能均衡，频率参考历史约 \(sessionsPerWeek) 次/周。"
        }

        return Result(
            planType: hadEnoughData ? planType : .balanced,
            sessionsPerWeek: sessionsPerWeek,
            summaryText: summary,
            hadEnoughData: hadEnoughData
        )
    }

    // MARK: - Private

    private static func minutes(in workouts: [WorkoutSnapshot], labels: Set<String>) -> Double {
        workouts.filter { labels.contains($0.activityLabel) }.reduce(0) { $0 + $1.durationMinutes }
    }

    /// 按自然周统计有锻炼的天数，再求 8 周滑动平均
    private static func averageSessionsPerWeek(
        workouts: [WorkoutSnapshot],
        referenceDate: Date,
        calendar: Calendar
    ) -> Int {
        let weekStarts = (0..<8).compactMap { offset -> Date? in
            guard let weekEnd = calendar.date(byAdding: .weekOfYear, value: -offset, to: referenceDate) else { return nil }
            return WorkoutPlanService.startOfWeek(weekEnd)
        }

        var counts: [Int] = []
        for weekStart in weekStarts {
            let weekEnd = calendar.date(byAdding: .day, value: 7, to: weekStart) ?? weekStart
            let days = Set(
                workouts
                    .filter { $0.date >= weekStart && $0.date < weekEnd }
                    .map { calendar.startOfDay(for: $0.date) }
            )
            if !days.isEmpty {
                counts.append(days.count)
            }
        }

        guard !counts.isEmpty else { return 4 }
        let average = Double(counts.reduce(0, +)) / Double(counts.count)
        return min(max(Int(average.rounded()), 2), 6)
    }

    private static func recommendPlanType(
        strengthShare: Double,
        cardioShare: Double,
        sessionsPerWeek: Int
    ) -> WorkoutPlanType {
        if cardioShare >= 0.70 {
            return .cardioFocus
        }
        if strengthShare >= 0.55 {
            if sessionsPerWeek >= 4 {
                return .threeDaySplitPlusCardio
            }
            if sessionsPerWeek >= 3 {
                return .threeDaySplit
            }
            return .balanced
        }
        if strengthShare >= 0.35, cardioShare >= 0.25 {
            return .balanced
        }
        if mindBodyDominance(strengthShare: strengthShare, cardioShare: cardioShare) {
            return .balanced
        }
        return .balanced
    }

    private static func mindBodyDominance(strengthShare: Double, cardioShare: Double) -> Bool {
        strengthShare < 0.35 && cardioShare < 0.50
    }

    private static func activityBreakdown(in workouts: [WorkoutSnapshot], totalMinutes: Double) -> [String] {
        guard totalMinutes > 0 else { return [] }
        var buckets: [String: Double] = [:]
        for item in workouts {
            buckets[item.activityLabel, default: 0] += item.durationMinutes
        }
        return buckets
            .sorted { $0.value > $1.value }
            .prefix(5)
            .map { label, minutes in
                let pct = Int((minutes / totalMinutes * 100).rounded())
                return "\(label) \(pct)%"
            }
    }
}
