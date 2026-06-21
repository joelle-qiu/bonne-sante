import Foundation
import SwiftData

/// 体检报告（OCR 导入，须用户校对后 `isVerified = true` 才参与评估）
/// @author jiali.qiu
@Model
final class Report {
    var id: UUID
    var fileName: String
    var sourceType: String
    var importDate: Date
    var examDate: Date?
    var isVerified: Bool
    var rawOCRText: String
    /// 主检医生建议（OCR/AI 提取，用户可校对）
    var recommendationsText: String = ""

    @Relationship(deleteRule: .cascade, inverse: \HealthMetric.report)
    var metrics: [HealthMetric]
    

    init(
        fileName: String,
        sourceType: String,
        examDate: Date? = nil,
        isVerified: Bool = false,
        rawOCRText: String = "",
        recommendationsText: String = ""
    ) {
        self.id = UUID()
        self.fileName = fileName
        self.sourceType = sourceType
        self.importDate = Date()
        self.examDate = examDate ?? Date()
        self.isVerified = isVerified
        self.rawOCRText = rawOCRText
        self.recommendationsText = recommendationsText
        self.metrics = []
    }
}
