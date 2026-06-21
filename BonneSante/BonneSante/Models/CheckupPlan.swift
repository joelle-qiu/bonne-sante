import Foundation
import SwiftData

/// 复查计划
/// @author jiali.qiu
@Model
final class CheckupPlan {
    var id: UUID
    var metricName: String
    var department: String = ""
    var seriesKey: String = ""
    var frequencyInMonths: Int
    var lastExamDate: Date
    var nextDueDate: Date
    var reminderDaysBefore: [Int]

    init(
        metricName: String,
        department: String = "",
        seriesKey: String = "",
        frequencyInMonths: Int,
        lastExamDate: Date,
        reminderDaysBefore: [Int] = [30, 7]
    ) {
        self.id = UUID()
        self.metricName = metricName
        self.department = department
        self.seriesKey = seriesKey
        self.frequencyInMonths = frequencyInMonths
        self.lastExamDate = lastExamDate
        self.nextDueDate = Calendar.current.date(
            byAdding: .month,
            value: frequencyInMonths,
            to: lastExamDate
        ) ?? lastExamDate
        self.reminderDaysBefore = reminderDaysBefore
    }
}
