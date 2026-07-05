import Foundation

/// 运动日历：月网格、热力强度、周统计（纯函数）
/// @author jiali.qiu
enum WorkoutCalendarEngine {

    struct DayCell: Identifiable, Equatable {
        var id: String
        var date: Date?
        var isPlaceholder: Bool
        var workoutCount: Int
        var totalMinutes: Double
        var totalCalories: Double
        var plannedTitle: String?
        var planCompleted: Bool
        /// 0=无锻炼，1–3=热力等级
        var heatLevel: Int
    }

    struct WeekStats: Equatable {
        var activeDays: Int
        var goalDays: Int
        var totalMinutes: Double
        var totalCalories: Double
    }

    /// 单日运动摘要（今日/本周仪表盘）
    struct DaySummary: Identifiable, Equatable {
        var id: String
        var date: Date
        var isToday: Bool
        var workoutCount: Int
        var totalMinutes: Double
        var totalCalories: Double
        var plannedType: String?
        var planTargetMinutes: Int
        var planTargetCalories: Double
        var planCompleted: Bool
        var heatLevel: Int
    }

    static func weekDaySummaries(
        for referenceDate: Date = Date(),
        workouts: [WorkoutSnapshot],
        planEntries: [WorkoutPlanEntry]
    ) -> [DaySummary] {
        let calendar = Calendar.current
        let weekStart = WorkoutPlanService.startOfWeek(referenceDate)
        return (0..<7).compactMap { offset -> DaySummary? in
            guard let date = calendar.date(byAdding: .day, value: offset, to: weekStart) else { return nil }
            return daySummary(for: date, workouts: workouts, planEntries: planEntries)
        }
    }

    static func daySummary(
        for date: Date,
        workouts: [WorkoutSnapshot],
        planEntries: [WorkoutPlanEntry]
    ) -> DaySummary {
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: date)
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart
        let dayWorkouts = workouts.filter { $0.date >= dayStart && $0.date < dayEnd }
        let minutes = dayWorkouts.reduce(0.0) { $0 + $1.durationMinutes }
        let calories = dayWorkouts.reduce(0.0) { $0 + $1.activeCalories }
        let plan = planEntry(on: date, entries: planEntries)
        return DaySummary(
            id: dayKey(dayStart),
            date: dayStart,
            isToday: calendar.isDateInToday(dayStart),
            workoutCount: dayWorkouts.count,
            totalMinutes: minutes,
            totalCalories: calories,
            plannedType: plan?.workoutType,
            planTargetMinutes: plan?.targetMinutes ?? 0,
            planTargetCalories: plan?.targetCalories ?? 0,
            planCompleted: plan?.isCompleted ?? false,
            heatLevel: heatLevel(count: dayWorkouts.count, minutes: minutes)
        )
    }

    static func todaySummary(
        workouts: [WorkoutSnapshot],
        planEntries: [WorkoutPlanEntry]
    ) -> DaySummary {
        daySummary(for: Date(), workouts: workouts, planEntries: planEntries)
    }

    static func startOfMonth(_ date: Date) -> Date {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month], from: date)
        return calendar.date(from: components) ?? calendar.startOfDay(for: date)
    }

    static func monthGrid(
        for month: Date,
        workouts: [WorkoutSnapshot],
        planEntries: [WorkoutPlanEntry]
    ) -> [DayCell] {
        let calendar = Calendar.current
        let monthStart = startOfMonth(month)
        guard let dayRange = calendar.range(of: .day, in: .month, for: monthStart),
              let monthEnd = calendar.date(byAdding: DateComponents(month: 1, day: -1), to: monthStart) else {
            return []
        }

        let firstWeekday = calendar.component(.weekday, from: monthStart)
        let leadingBlanks = (firstWeekday + 5) % 7

        var cells: [DayCell] = []
        for _ in 0..<leadingBlanks {
            cells.append(placeholderCell(index: cells.count))
        }

        for day in dayRange {
            guard let date = calendar.date(byAdding: .day, value: day - 1, to: monthStart) else { continue }
            let dayStart = calendar.startOfDay(for: date)
            let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart
            let dayWorkouts = workouts.filter { $0.date >= dayStart && $0.date < dayEnd }
            let minutes = dayWorkouts.reduce(0.0) { $0 + $1.durationMinutes }
            let calories = dayWorkouts.reduce(0.0) { $0 + $1.activeCalories }
            let plan = planEntry(on: date, entries: planEntries)

            cells.append(
                DayCell(
                    id: dayKey(dayStart),
                    date: dayStart,
                    isPlaceholder: false,
                    workoutCount: dayWorkouts.count,
                    totalMinutes: minutes,
                    totalCalories: calories,
                    plannedTitle: plan?.workoutType,
                    planCompleted: plan?.isCompleted ?? false,
                    heatLevel: heatLevel(count: dayWorkouts.count, minutes: minutes)
                )
            )
        }

        while cells.count % 7 != 0 {
            cells.append(placeholderCell(index: cells.count))
        }

        _ = monthEnd
        return cells
    }

    struct MonthStats: Equatable {
        var activeDays: Int
        var totalMinutes: Double
        var totalCalories: Double
        var plannedDays: Int
        var completedPlanDays: Int
    }

    static func monthStats(
        for month: Date,
        workouts: [WorkoutSnapshot],
        planEntries: [WorkoutPlanEntry]
    ) -> MonthStats {
        let calendar = Calendar.current
        let monthStart = startOfMonth(month)
        guard let monthEnd = calendar.date(byAdding: DateComponents(month: 1), to: monthStart) else {
            return MonthStats(activeDays: 0, totalMinutes: 0, totalCalories: 0, plannedDays: 0, completedPlanDays: 0)
        }

        let monthWorkouts = workouts.filter { $0.date >= monthStart && $0.date < monthEnd }
        let activeDayKeys = Set(monthWorkouts.map { dayKey(calendar.startOfDay(for: $0.date)) })

        var plannedDays = 0
        var completedPlanDays = 0
        for entry in planEntries {
            guard let sessionDate = WorkoutPlanService.sessionDate(for: entry),
                  sessionDate >= monthStart, sessionDate < monthEnd else { continue }
            plannedDays += 1
            if entry.isCompleted { completedPlanDays += 1 }
        }

        return MonthStats(
            activeDays: activeDayKeys.count,
            totalMinutes: monthWorkouts.reduce(0) { $0 + $1.durationMinutes },
            totalCalories: monthWorkouts.reduce(0) { $0 + $1.activeCalories },
            plannedDays: plannedDays,
            completedPlanDays: completedPlanDays
        )
    }

    static func weekStats(for referenceDate: Date, workouts: [WorkoutSnapshot], goalDays: Int = 5) -> WeekStats {
        let calendar = Calendar.current
        let weekStart = WorkoutPlanService.startOfWeek(referenceDate)
        let weekEnd = calendar.date(byAdding: .day, value: 7, to: weekStart) ?? weekStart

        let weekWorkouts = workouts.filter { $0.date >= weekStart && $0.date < weekEnd }
        let activeDayKeys = Set(weekWorkouts.map { dayKey(calendar.startOfDay(for: $0.date)) })

        return WeekStats(
            activeDays: activeDayKeys.count,
            goalDays: goalDays,
            totalMinutes: weekWorkouts.reduce(0) { $0 + $1.durationMinutes },
            totalCalories: weekWorkouts.reduce(0) { $0 + $1.activeCalories }
        )
    }

    static func workouts(on day: Date, from workouts: [WorkoutSnapshot]) -> [WorkoutSnapshot] {
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: day)
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart
        return workouts
            .filter { $0.date >= dayStart && $0.date < dayEnd }
            .sorted { $0.date < $1.date }
    }

    // MARK: - Private

    private static func placeholderCell(index: Int) -> DayCell {
        DayCell(
            id: "placeholder-\(index)",
            date: nil,
            isPlaceholder: true,
            workoutCount: 0,
            totalMinutes: 0,
            totalCalories: 0,
            plannedTitle: nil,
            planCompleted: false,
            heatLevel: 0
        )
    }

    private static func dayKey(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private static func heatLevel(count: Int, minutes: Double) -> Int {
        guard count > 0 else { return 0 }
        if count >= 2 || minutes >= 50 { return 3 }
        if minutes >= 25 { return 2 }
        return 1
    }

    private static func planEntry(on date: Date, entries: [WorkoutPlanEntry]) -> WorkoutPlanEntry? {
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: date)
        return entries.first { entry in
            guard let sessionDate = WorkoutPlanService.sessionDate(for: entry) else { return false }
            return calendar.isDate(sessionDate, inSameDayAs: dayStart)
        }
    }
}
