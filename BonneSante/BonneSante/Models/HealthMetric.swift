import Foundation
import SwiftData

/// 单条体检指标
/// @author jiali.qiu
@Model
final class HealthMetric {
    var id: UUID
    var name: String
    var value: Double
    var valueText: String
    var unit: String
    var referenceRange: String
    var isAbnormal: Bool
    var date: Date
    /// 检验 / 异常发现 / 其他
    var category: String = "检验"
    /// 报告章节归类（一般检查、血常规、影像检查等）
    var reportSection: String = ""
    /// 异常严重度 1–5（5 最高），用于摘要与趋势排序
    var severityRank: Int = 0
    /// 简要临床判断依据（DeepSeek / 本地规则）
    var assessmentNote: String = ""
    /// 形态标签（cyst/nodule/hemangioma…，由 DeepSeek 标注）
    var morphologyTag: String = ""
    /// 部位标签（liver/cervix/spine…，由 DeepSeek 标注）
    var organSiteTag: String = ""
    var report: Report?

    init(
        name: String,
        value: Double,
        valueText: String,
        unit: String,
        referenceRange: String = "",
        isAbnormal: Bool = false,
        date: Date = Date(),
        category: String = "检验",
        reportSection: String = "",
        severityRank: Int = 0,
        assessmentNote: String = "",
        morphologyTag: String = "",
        organSiteTag: String = "",
        report: Report? = nil
    ) {
        self.id = UUID()
        self.name = name
        self.value = value
        self.valueText = valueText
        self.unit = unit
        self.referenceRange = referenceRange
        self.isAbnormal = isAbnormal
        self.date = date
        self.category = category
        self.reportSection = reportSection.isEmpty
            ? ReportMetricCategory.inferSection(name: name, valueText: valueText)
            : reportSection
        self.severityRank = severityRank
        self.assessmentNote = assessmentNote
        self.morphologyTag = morphologyTag
        self.organSiteTag = organSiteTag
        self.report = report
    }
}
