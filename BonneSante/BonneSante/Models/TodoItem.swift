import Foundation
import SwiftData

/// 待办事项
/// @author jiali.qiu
@Model
final class TodoItem {
    var id: UUID
    var title: String
    var dueDate: Date
    var location: String?
    var notes: String?
    var source: String
    var relatedMetric: String?
    var department: String = ""
    var seriesKey: String = ""
    var isCompleted: Bool
    var createdDate: Date

    init(
        title: String,
        dueDate: Date,
        location: String? = nil,
        notes: String? = nil,
        source: TodoSource = .fitness,
        relatedMetric: String? = nil,
        department: String = "",
        seriesKey: String = "",
        isCompleted: Bool = false
    ) {
        self.id = UUID()
        self.title = title
        self.dueDate = dueDate
        self.location = location
        self.notes = notes
        self.source = source.rawValue
        self.relatedMetric = relatedMetric
        self.department = department
        self.seriesKey = seriesKey
        self.isCompleted = isCompleted
        self.createdDate = Date()
    }

    var sourceType: TodoSource {
        TodoSource(rawValue: source) ?? .manual
    }
}

enum TodoSource: String, CaseIterable {
    case fitness
    case manual
    case risk
    case checkup
    case appointment

    /// 训练 Tab 展示的来源（排除历史复查待办）
    var isFitnessTask: Bool {
        self == .fitness || self == .manual
    }
}
