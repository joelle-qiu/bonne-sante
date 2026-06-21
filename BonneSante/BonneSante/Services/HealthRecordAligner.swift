import Foundation
import SwiftData

/// 零散门诊/OCR 数据与健康档案（趋势引擎）指标名对齐
/// @author jiali.qiu
enum HealthRecordAligner {

    /// 对齐整份导入草稿（指标去重 + 规范命名 + 组合指标拆分）
    static func align(draft: ReportImporter.ImportDraft) -> ReportImporter.ImportDraft {
        var copy = draft
        copy.findings = ImagingFollowUpEnricher.enrichAll(copy.findings)
        let promoted = ReportMetricExpander.promoteLabFindings(findings: copy.findings, metrics: copy.metrics)
        copy.findings = promoted.findings
        copy.metrics = align(metrics: ReportMetricExpander.expand(promoted.metrics))
        copy.findings = align(findings: copy.findings)
        return copy
    }

    /// 检验指标：canonical key 去重 + 统一展示名
    static func align(metrics: [ReportImporter.DraftMetric]) -> [ReportImporter.DraftMetric] {
        var byKey: [String: ReportImporter.DraftMetric] = [:]
        for var metric in metrics {
            metric = alignMetric(metric)
            let key = MetricNameCanonicalizer.canonicalKey(for: metric.name)
            if let existing = byKey[key] {
                byKey[key] = preferMetric(existing, metric)
            } else {
                byKey[key] = metric
            }
        }
        return byKey.values.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// 检查结论：归一标题 + 去重
    static func align(findings: [ReportImporter.DraftFinding]) -> [ReportImporter.DraftFinding] {
        let enriched = ImagingFollowUpEnricher.enrichAll(findings)
        var byKey: [String: ReportImporter.DraftFinding] = [:]
        for var finding in enriched {
            guard !shouldSkipFinding(finding) else { continue }
            finding = alignFinding(finding)
            guard !ReportMetricNormalizer.isInsignificantImagingLine(
                finding.detail.isEmpty ? finding.title : finding.title + finding.detail
            ) || finding.isAbnormal else { continue }
            let key = findingCanonicalKey(for: finding)
            if let existing = byKey[key] {
                byKey[key] = preferFinding(existing, finding)
            } else {
                byKey[key] = finding
            }
        }
        return byKey.values.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    /// 校对页提示：说明入库后将与哪类档案趋势合并
    static func alignmentHint(forMetricName name: String) -> String? {
        let trimmed = name.trimmingCharacters(in: CharacterSet.whitespaces)
        guard trimmed.count >= 2 else { return nil }
        let resolution = MetricNameCanonicalizer.resolve(trimmed)
        guard resolution.confidence >= 0.42, !resolution.canonicalKey.hasPrefix("raw.") else { return nil }
        if resolution.confidence >= 0.75 {
            return "对齐档案：\(resolution.displayName)"
        }
        return "可能对齐：\(resolution.displayName)"
    }

    static func alignmentHint(forFinding finding: ReportImporter.DraftFinding) -> String? {
        let trimmed = finding.title.trimmingCharacters(in: CharacterSet.whitespaces)
        guard trimmed.count >= 2 else { return nil }
        let stub = HealthMetric(
            name: trimmed,
            value: 0,
            valueText: finding.detail,
            unit: "",
            referenceRange: finding.category,
            isAbnormal: finding.isAbnormal,
            category: "异常发现"
        )
        guard let entry = FindingNameCanonicalizer.entries(from: stub).first else { return nil }
        return "对齐档案：\(entry.displayName)"
    }

    /// 结论去重 key（供 AI 合并使用）
    static func findingKey(for finding: ReportImporter.DraftFinding) -> String {
        findingCanonicalKey(for: finding)
    }

    // MARK: - Private

    private static func shouldSkipFinding(_ finding: ReportImporter.DraftFinding) -> Bool {
        let title = finding.title.trimmingCharacters(in: CharacterSet.whitespaces)
        if title.isEmpty { return true }
        // 两字器官名（肝脏/乳腺/子宫等）有临床内容时不丢弃
        if title.count < 3, !ReportMetricNormalizer.hasClinicalFindingContent(finding) { return true }
        let stripped = title
            .replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "：", with: "")
            .replacingOccurrences(of: ":", with: "")
            .trimmingCharacters(in: CharacterSet.whitespaces)
        let fieldOnly = ["检查部位", "检查描述", "检查所见", "诊断结论"]
        if fieldOnly.contains(stripped) { return true }
        if title.contains("检查部位") && title.count < 12 { return true }
        if title.hasPrefix("*注") || title.contains("参考区间显示") { return true }
        if title.hasPrefix("#") || title.contains("**") { return true }
        return false
    }

    private static func alignMetric(_ metric: ReportImporter.DraftMetric) -> ReportImporter.DraftMetric {
        var copy = ReportMetricNormalizer.polish(metric)
        copy.name = preferredMetricName(copy.name)
        ReportMetricCategory.assignSection(to: &copy)
        return copy
    }

    private static func preferredMetricName(_ name: String) -> String {
        let resolution = MetricNameCanonicalizer.resolve(name)
        if resolution.confidence >= 0.42 {
            return resolution.displayName
        }
        return ReportMetricNormalizer.normalizeName(name)
    }

    private static func preferMetric(
        _ left: ReportImporter.DraftMetric,
        _ right: ReportImporter.DraftMetric
    ) -> ReportImporter.DraftMetric {
        if left.value == 0, right.value != 0 { return right }
        if right.value == 0, left.value != 0 { return left }
        if left.referenceRange.isEmpty, !right.referenceRange.isEmpty { return right }
        if left.valueText.count < right.valueText.count { return right }
        return left
    }

    private static func alignFinding(_ finding: ReportImporter.DraftFinding) -> ReportImporter.DraftFinding {
        var copy = ReportMetricNormalizer.enrichClinicalFinding(finding)
        let stub = findingStub(for: copy)
        if let entry = FindingNameCanonicalizer.entries(from: stub).first {
            copy.title = entry.displayName
            if copy.detail.isEmpty, !entry.detailText.isEmpty, entry.detailText != entry.displayName {
                copy.detail = entry.detailText
            }
            copy.category = categoryForFindingKey(entry.canonicalKey, fallback: copy.category)
        } else if !copy.taxonomyTags.briefLabel.isEmpty, copy.title.count < 4 {
            copy.title = copy.taxonomyTags.briefLabel
        }
        let inspectBlob = copy.detail.isEmpty ? copy.title : "\(copy.title) \(copy.detail)"
        if ReportMetricNormalizer.isInsignificantImagingLine(copy.title)
            && ReportMetricNormalizer.isInsignificantImagingLine(
                inspectBlob + copy.conclusion + copy.assessmentNote
            ) {
            copy.isAbnormal = false
        }
        return copy
    }

    private static func findingStub(for finding: ReportImporter.DraftFinding) -> HealthMetric {
        var valueText = finding.detail.isEmpty ? finding.title : "\(finding.title) \(finding.detail)"
        let conclusion = finding.conclusion.trimmingCharacters(in: CharacterSet.whitespaces)
        if !conclusion.isEmpty, !valueText.contains(conclusion) {
            valueText += " \(conclusion)"
        }
        return HealthMetric(
            name: finding.title,
            value: FindingSizeParser.maxMillimeters(in: valueText) ?? 0,
            valueText: valueText,
            unit: "",
            referenceRange: finding.category,
            isAbnormal: finding.isAbnormal,
            category: "异常发现",
            assessmentNote: finding.assessmentNote,
            morphologyTag: finding.morphology,
            organSiteTag: finding.organSite
        )
    }

    private static func findingCanonicalKey(for finding: ReportImporter.DraftFinding) -> String {
        let stub = findingStub(for: finding)
        let base = FindingNameCanonicalizer.entries(from: stub).first?.canonicalKey
            ?? "finding.\(RiskAnalyzer.normalize(finding.title))"
        // 跨次随访粘贴（同 canonicalKey、不同 visitDate）须保留为独立条目，供按日期拆分与趋势对比
        if let visitDate = finding.visitDate {
            return base + "|" + ReportDisplayFormatter.examDateLabel(visitDate)
        }
        return base
    }

    private static func categoryForFindingKey(_ key: String, fallback: String) -> String {
        if key.hasPrefix("gyn.") { return "妇科" }
        if key.hasPrefix("exam.ecg") { return "心电图" }
        if key.hasPrefix("exam.") { return "体格检查" }
        if key.hasPrefix("imaging.") { return "影像" }
        return fallback.isEmpty ? "其他" : fallback
    }

    private static func preferFinding(
        _ left: ReportImporter.DraftFinding,
        _ right: ReportImporter.DraftFinding
    ) -> ReportImporter.DraftFinding {
        var chosen: ReportImporter.DraftFinding
        if left.detail.isEmpty, !right.detail.isEmpty {
            chosen = right
        } else if left.detail.count < right.detail.count {
            chosen = right
        } else {
            chosen = left
        }
        let other = chosen.id == left.id ? right : left
        if chosen.conclusion.isEmpty, !other.conclusion.isEmpty {
            chosen.conclusion = other.conclusion
        }
        if chosen.assessmentNote.isEmpty, !other.assessmentNote.isEmpty {
            chosen.assessmentNote = other.assessmentNote
        } else if !other.conclusion.isEmpty,
                  !chosen.assessmentNote.contains(other.conclusion),
                  ReportMetricNormalizer.isPlaceholderAssessmentNote(chosen.assessmentNote) {
            chosen.assessmentNote = "结论：\(other.conclusion)"
        }
        return chosen
    }
}
