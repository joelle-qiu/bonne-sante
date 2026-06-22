import Foundation
import SwiftData

/// 单条周训练安排
/// @author jiali.qiu
@Model
final class WorkoutPlanEntry {
    var id: UUID
    /// Calendar.weekday：1=周日 … 2=周一
    var dayOfWeek: Int
    var workoutType: String
    var targetMinutes: Int
    /// low | medium | high
    var intensity: String
    var cyclePhase: String
    var weekStartDate: Date
    var notes: String
    /// 心情模式温馨提醒（如「别忘带泳帽哦～」）
    var moodReminderText: String
    /// 本场目标消耗（kcal）
    var targetCalories: Double
    /// 换动作后 AI 重评估说明
    var replanNote: String
    /// engine | ai
    var source: String
    var isCompleted: Bool
    var completedAt: Date?
    var createdAt: Date

    init(
        dayOfWeek: Int,
        workoutType: String,
        targetMinutes: Int,
        intensity: String,
        cyclePhase: String,
        weekStartDate: Date,
        notes: String = "",
        moodReminderText: String = "",
        targetCalories: Double = 0,
        replanNote: String = "",
        source: String = "engine",
        isCompleted: Bool = false,
        completedAt: Date? = nil
    ) {
        self.id = UUID()
        self.dayOfWeek = dayOfWeek
        self.workoutType = workoutType
        self.targetMinutes = targetMinutes
        self.intensity = intensity
        self.cyclePhase = cyclePhase
        self.weekStartDate = weekStartDate
        self.notes = notes
        self.moodReminderText = moodReminderText
        self.targetCalories = targetCalories
        self.replanNote = replanNote
        self.source = source
        self.isCompleted = isCompleted
        self.completedAt = completedAt
        self.createdAt = Date()
    }

    var intensityLabel: String {
        switch intensity {
        case "low": return "低强度"
        case "high": return "高强度"
        default: return "中等强度"
        }
    }

    var weekdayLabel: String {
        WorkoutPlanEntry.weekdayLabels[safe: dayOfWeek - 1] ?? "周?"
    }

    private static let weekdayLabels = ["周日", "周一", "周二", "周三", "周四", "周五", "周六"]

    /// 周一至周日（Calendar.weekday：2=周一 … 1=周日）
    static let weekdayOptions: [(day: Int, label: String)] = [
        (2, "周一"), (3, "周二"), (4, "周三"), (5, "周四"),
        (6, "周五"), (7, "周六"), (1, "周日")
    ]

    /// 周一优先排序键（周一=1 … 周日=7）
    static func mondayFirstSortOrder(for dayOfWeek: Int) -> Int {
        dayOfWeek == 1 ? 7 : dayOfWeek - 1
    }

    /// 本周安排等 UI：按周一至周日排序
    static func sortedMondayFirst(_ entries: [WorkoutPlanEntry]) -> [WorkoutPlanEntry] {
        entries.sorted {
            let lhs = mondayFirstSortOrder(for: $0.dayOfWeek)
            let rhs = mondayFirstSortOrder(for: $1.dayOfWeek)
            if lhs == rhs { return $0.createdAt < $1.createdAt }
            return lhs < rhs
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
