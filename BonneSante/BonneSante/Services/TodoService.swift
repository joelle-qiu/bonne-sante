import Foundation
import SwiftData
import UserNotifications

/// 待办本地通知
/// @author jiali.qiu
enum TodoService {

    static func requestAuthorization() async {
        let center = UNUserNotificationCenter.current()
        _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
    }

    static func scheduleReminders(for item: TodoItem) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: notificationIDs(for: item.id))

        let content = UNMutableNotificationContent()
        switch item.sourceType {
        case .fitness:
            content.title = "训练提醒"
        case .appointment:
            content.title = "门诊提醒"
        default:
            content.title = "Bonne-Santé 提醒"
        }
        content.body = item.title
        content.sound = .default

        let triggerDate = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: item.dueDate
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: triggerDate, repeats: false)
        let request = UNNotificationRequest(
            identifier: primaryID(for: item.id),
            content: content,
            trigger: trigger
        )
        center.add(request)
    }

    static func scheduleCheckupReminders(for plan: CheckupPlan) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: checkupIDs(for: plan.id))

        for daysBefore in plan.reminderDaysBefore {
            guard let fireDate = Calendar.current.date(byAdding: .day, value: -daysBefore, to: plan.nextDueDate),
                  fireDate > Date() else { continue }

            let content = UNMutableNotificationContent()
            content.title = "复查提醒"
            content.body = "\(plan.metricName) 复查将在 \(daysBefore) 天后到期"
            content.sound = .default

            let components = Calendar.current.dateComponents([.year, .month, .day, .hour], from: fireDate)
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            let id = "\(checkupPrefix)\(plan.id.uuidString)-\(daysBefore)"
            center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
        }
    }

    static func cancelNotifications(for itemID: UUID) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: notificationIDs(for: itemID)
        )
    }

    static func cancelCheckupReminders(for planID: UUID) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: checkupIDs(for: planID)
        )
    }

    static let workoutMorningNotificationID = "workout-morning-today"

    /// 仅注册「今日训练」单条晨间提醒（会先移除同 ID 旧请求）
    static func scheduleWorkoutMorningReminder(fireDate: Date, body: String) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [workoutMorningNotificationID])

        let content = UNMutableNotificationContent()
        content.title = "今日训练"
        content.body = body
        content.sound = .default

        let triggerDate = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: fireDate
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: triggerDate, repeats: false)
        let request = UNNotificationRequest(
            identifier: workoutMorningNotificationID,
            content: content,
            trigger: trigger
        )
        center.add(request)
    }

    static func cancelWorkoutMorningReminder() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: [workoutMorningNotificationID]
        )
    }

    private static let checkupPrefix = "checkup-"
    private static func primaryID(for id: UUID) -> String { "todo-\(id.uuidString)" }
    private static func notificationIDs(for id: UUID) -> [String] { [primaryID(for: id)] }
    private static func checkupIDs(for id: UUID) -> [String] {
        [30, 7].map { "\(checkupPrefix)\(id.uuidString)-\($0)" }
    }
}
