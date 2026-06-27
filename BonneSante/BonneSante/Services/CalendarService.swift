import Foundation
import EventKit

/// 门诊预约写入系统日历（EventKit）
/// @author jiali.qiu
enum CalendarService {

    enum CalendarError: LocalizedError {
        case accessDenied
        case saveFailed
        case eventNotFound

        var errorDescription: String? {
            switch self {
            case .accessDenied: return "未获得日历访问权限，请在系统设置中允许 Bonne-Santé 访问日历"
            case .saveFailed: return "无法写入系统日历"
            case .eventNotFound: return "日历事件不存在或已被删除"
            }
        }
    }

    @MainActor
    static func requestAccess() async -> Bool {
        let store = EKEventStore()
        return await withCheckedContinuation { continuation in
            store.requestFullAccessToEvents { granted, _ in
                continuation.resume(returning: granted)
            }
        }
    }

    @MainActor
    static func addAppointment(for item: TodoItem) async throws -> String {
        guard await requestAccess() else { throw CalendarError.accessDenied }

        let store = EKEventStore()
        let event = EKEvent(eventStore: store)
        event.title = item.title
        event.startDate = item.dueDate
        event.endDate = Calendar.current.date(byAdding: .hour, value: 1, to: item.dueDate) ?? item.dueDate
        event.location = item.location
        event.notes = item.notes
        event.calendar = store.defaultCalendarForNewEvents

        try store.save(event, span: .thisEvent, commit: true)
        guard let identifier = event.eventIdentifier else { throw CalendarError.saveFailed }
        return identifier
    }

    @MainActor
    static func removeEvent(identifier: String) throws {
        guard !identifier.isEmpty else { return }
        let store = EKEventStore()
        guard let event = store.event(withIdentifier: identifier) else {
            throw CalendarError.eventNotFound
        }
        try store.remove(event, span: .thisEvent, commit: true)
    }
}
