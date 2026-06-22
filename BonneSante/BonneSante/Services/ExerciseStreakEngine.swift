import Foundation

/// 连续运动天数与 7 天满月勋章（HealthKit 锻炼 + 训练计划完成）
/// @author jiali.qiu
enum ExerciseStreakEngine {

    static let badgeGoalDays = 7
    private static let unlockKey = "bonnesante_exercise_streak_badge_unlocked"

    struct DayDot: Identifiable, Equatable {
        var id: String
        var weekdayShort: String
        var isActive: Bool
        var isToday: Bool
    }

    struct Status: Equatable {
        var currentStreak: Int
        var isBadgeUnlocked: Bool
        var daysUntilUnlock: Int
        var recentSevenDays: [DayDot]

        static let empty = Status(
            currentStreak: 0,
            isBadgeUnlocked: false,
            daysUntilUnlock: badgeGoalDays,
            recentSevenDays: []
        )
    }

    /// 评估当前连续运动 streak 与 7 日进度
    static func evaluate(
        workouts: [WorkoutSnapshot],
        completedPlanDates: [Date],
        referenceDate: Date = Date()
    ) -> Status {
        let calendar = Calendar.current
        let completedKeys = Set(completedPlanDates.map { dayKey($0, calendar: calendar) })
        let streak = currentStreak(
            workouts: workouts,
            completedDayKeys: completedKeys,
            referenceDate: referenceDate,
            calendar: calendar
        )
        persistUnlockIfNeeded(streak: streak)
        let unlocked = isBadgePermanentlyUnlocked || streak >= badgeGoalDays
        let dots = recentSevenDayDots(
            workouts: workouts,
            completedDayKeys: completedKeys,
            referenceDate: referenceDate,
            calendar: calendar
        )
        let until = unlocked ? 0 : max(badgeGoalDays - streak, 0)

        return Status(
            currentStreak: streak,
            isBadgeUnlocked: unlocked,
            daysUntilUnlock: until,
            recentSevenDays: dots
        )
    }

    static var isBadgePermanentlyUnlocked: Bool {
        UserDefaults.standard.bool(forKey: unlockKey)
    }

    static func persistUnlockIfNeeded(streak: Int) {
        guard streak >= badgeGoalDays else { return }
        UserDefaults.standard.set(true, forKey: unlockKey)
    }

    // MARK: - Private

    private static func currentStreak(
        workouts: [WorkoutSnapshot],
        completedDayKeys: Set<String>,
        referenceDate: Date,
        calendar: Calendar
    ) -> Int {
        var cursor = calendar.startOfDay(for: referenceDate)
        if !isActiveDay(cursor, workouts: workouts, completedDayKeys: completedDayKeys, calendar: calendar),
           let yesterday = calendar.date(byAdding: .day, value: -1, to: cursor) {
            cursor = yesterday
        }

        var streak = 0
        while isActiveDay(cursor, workouts: workouts, completedDayKeys: completedDayKeys, calendar: calendar) {
            streak += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
            if streak > 120 { break }
        }
        return streak
    }

    private static func recentSevenDayDots(
        workouts: [WorkoutSnapshot],
        completedDayKeys: Set<String>,
        referenceDate: Date,
        calendar: Calendar
    ) -> [DayDot] {
        let labels = ["日", "一", "二", "三", "四", "五", "六"]
        let today = calendar.startOfDay(for: referenceDate)
        return (0..<badgeGoalDays).reversed().compactMap { offset -> DayDot? in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
            let weekday = calendar.component(.weekday, from: date)
            let label = labels[safe: weekday - 1] ?? "?"
            return DayDot(
                id: dayKey(date, calendar: calendar),
                weekdayShort: label,
                isActive: isActiveDay(date, workouts: workouts, completedDayKeys: completedDayKeys, calendar: calendar),
                isToday: offset == 0
            )
        }
    }

    private static func isActiveDay(
        _ date: Date,
        workouts: [WorkoutSnapshot],
        completedDayKeys: Set<String>,
        calendar: Calendar
    ) -> Bool {
        let key = dayKey(date, calendar: calendar)
        if completedDayKeys.contains(key) { return true }
        return workouts.contains { calendar.isDate($0.date, inSameDayAs: date) }
    }

    private static func dayKey(_ date: Date, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = calendar.timeZone
        return formatter.string(from: calendar.startOfDay(for: date))
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
