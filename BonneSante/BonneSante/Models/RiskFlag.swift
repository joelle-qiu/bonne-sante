import Foundation
import SwiftData

/// 健康风险标记（规则引擎输出，非医学诊断）
/// @author jiali.qiu
@Model
final class RiskFlag {
    var id: UUID
    var metricName: String
    var severity: String
    var currentValue: String
    var trendDescription: String
    var suggestedAction: String
    /// 建议复查间隔（月），来自风险规则
    var checkupMonths: Int = 3
    /// 临床科室（与异常指标摘要一致）
    var department: String = ""
    /// 序列 key，用于待办/复查计划去重
    var seriesKey: String = ""
    var createdDate: Date
    var isResolved: Bool

    static let medicalDisclaimer = "仅供参考，请遵医嘱"

    init(
        metricName: String,
        severity: RiskSeverity,
        currentValue: String,
        trendDescription: String,
        suggestedAction: String,
        checkupMonths: Int = 3,
        department: String = "",
        seriesKey: String = "",
        isResolved: Bool = false
    ) {
        self.id = UUID()
        self.metricName = metricName
        self.severity = severity.rawValue
        self.currentValue = currentValue
        self.trendDescription = trendDescription
        self.suggestedAction = suggestedAction
        self.checkupMonths = checkupMonths
        self.department = department
        self.seriesKey = seriesKey
        self.createdDate = Date()
        self.isResolved = isResolved
    }

    var severityLevel: RiskSeverity {
        RiskSeverity(rawValue: severity) ?? .low
    }
}

enum RiskSeverity: String, CaseIterable {
    case low
    case medium
    case high
}
