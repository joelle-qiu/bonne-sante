import Foundation
import SwiftData

/// 训练日晨间提醒：仅当天一场、可配置时间、与设置开关联动
/// @author jiali.qiu
enum WorkoutMorningReminderService {

    /// 清除旧版「整周预排」待办及其本地通知
    static func purgeLegacyPlanReminderTodos(modelContext: ModelContext) {
        let descriptor = FetchDescriptor<TodoItem>()
        guard let todos = try? modelContext.fetch(descriptor) else { return }
        var changed = false
        for todo in todos where todo.sourceType == .fitness && !todo.seriesKey.isEmpty {
            TodoService.cancelNotifications(for: todo.id)
            modelContext.delete(todo)
            changed = true
        }
        if changed {
            try? modelContext.save()
        }
    }

    /// 根据设置与今日排课，注册或取消「今日训练」单条提醒
    static func sync(modelContext: ModelContext) {
        purgeLegacyPlanReminderTodos(modelContext: modelContext)
        TodoService.cancelWorkoutMorningReminder()

        let settings = loadSettings(modelContext)
        guard settings.workoutMorningReminderEnabled else { return }

        let weekStart = WorkoutPlanService.startOfWeek()
        let entries = WorkoutPlanService.entriesForWeek(weekStart, modelContext: modelContext)
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        guard let todayEntry = entries.first(where: { entry in
            guard !entry.isCompleted,
                  let sessionDate = WorkoutPlanService.sessionDate(for: entry) else { return false }
            return calendar.isDate(sessionDate, inSameDayAs: today)
        }) else { return }

        var components = calendar.dateComponents([.year, .month, .day], from: today)
        components.hour = min(max(settings.workoutMorningReminderHour, 0), 23)
        components.minute = min(max(settings.workoutMorningReminderMinute, 0), 59)
        guard let fireDate = calendar.date(from: components), fireDate > Date() else { return }

        let body = "\(todayEntry.workoutType) · \(todayEntry.targetMinutes) 分钟"
        TodoService.scheduleWorkoutMorningReminder(fireDate: fireDate, body: body)
    }

    private static func loadSettings(_ modelContext: ModelContext) -> UserSettings {
        let descriptor = FetchDescriptor<UserSettings>()
        if let existing = try? modelContext.fetch(descriptor).first {
            return existing
        }
        let created = UserSettings()
        modelContext.insert(created)
        try? modelContext.save()
        return created
    }
}
