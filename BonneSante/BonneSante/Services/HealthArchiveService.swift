import Foundation
import SwiftData

/// 校验入库 + 风险重算（未校对报告不参与 Engine）
/// @author jiali.qiu
enum HealthArchiveService {

    /// 按就诊日期拆分入库；无 visitDate 时合并为一份报告
    @MainActor
    static func saveVerifiedReport(
        draft: ReportImporter.ImportDraft,
        editedMetrics: [ReportImporter.DraftMetric],
        editedFindings: [ReportImporter.DraftFinding] = [],
        recommendationsText: String = "",
        modelContext: ModelContext
    ) throws -> Report {
        let reports = try saveVerifiedReports(
            draft: draft,
            editedMetrics: editedMetrics,
            editedFindings: editedFindings,
            recommendationsText: recommendationsText,
            modelContext: modelContext
        )
        guard let first = reports.first else {
            throw NSError(domain: "HealthArchive", code: 1, userInfo: [NSLocalizedDescriptionKey: "未能创建报告"])
        }
        return first
    }

    /// 按 visitDate 拆分为多份 Report，便于跨次检查趋势对比
    @MainActor
    static func saveVerifiedReports(
        draft: ReportImporter.ImportDraft,
        editedMetrics: [ReportImporter.DraftMetric],
        editedFindings: [ReportImporter.DraftFinding] = [],
        recommendationsText: String = "",
        modelContext: ModelContext
    ) throws -> [Report] {
        let recText = recommendationsText.isEmpty
            ? draft.recommendations.joined(separator: "\n")
            : recommendationsText

        let batches = groupByVisitDate(
            metrics: HealthRecordAligner.align(metrics: editedMetrics),
            findings: HealthRecordAligner.align(findings: editedFindings),
            defaultDate: draft.examDate
        )

        var saved: [Report] = []
        let multiBatch = batches.count > 1

        for batch in batches {
            let fileName = multiBatch
                ? ReportDisplayFormatter.preferredFileName(
                    examDate: batch.date,
                    original: "\(draft.fileName) \(ReportDisplayFormatter.examDateLabel(batch.date))"
                )
                : ReportDisplayFormatter.preferredFileName(examDate: batch.date, original: draft.fileName)

            let report = Report(
                fileName: fileName,
                sourceType: draft.sourceType,
                examDate: batch.date,
                isVerified: true,
                rawOCRText: draft.rawText,
                recommendationsText: recText
            )
            modelContext.insert(report)

            for item in batch.metrics {
                let name = item.name.trimmingCharacters(in: CharacterSet.whitespaces)
                guard !name.isEmpty else { continue }
                let section = item.section.isEmpty
                    ? ReportMetricCategory.inferSection(name: item.name, valueText: item.valueText)
                    : item.section
                let metric = HealthMetric(
                    name: name,
                    value: item.value,
                    valueText: item.valueText.isEmpty ? String(item.value) : item.valueText,
                    unit: item.unit,
                    referenceRange: item.referenceRange,
                    isAbnormal: item.isAbnormal,
                    date: batch.date,
                    category: "检验",
                    reportSection: section,
                    severityRank: item.severityRank,
                    assessmentNote: item.assessmentNote,
                    report: report
                )
                modelContext.insert(metric)
                report.metrics.append(metric)
            }

            for finding in batch.findings {
                let isImaging = finding.category == "影像"
                    || finding.category == "心电图"
                    || ReportMetricCategory.sectionForFinding(category: finding.category) == "影像检查"
                let enrichedFinding = ImagingFollowUpEnricher.enrich(finding)
                guard enrichedFinding.isAbnormal || isImaging || !enrichedFinding.conclusion.isEmpty else { continue }

                let title = enrichedFinding.title.trimmingCharacters(in: CharacterSet.whitespaces)
                guard !title.isEmpty else { continue }
                let detail = enrichedFinding.detail.trimmingCharacters(in: CharacterSet.whitespaces)
                let conclusion = enrichedFinding.conclusion.trimmingCharacters(in: CharacterSet.whitespaces)
                var valueText: String
                if detail.isEmpty || detail == title {
                    valueText = title
                } else {
                    valueText = "\(title)：\(detail)"
                }
                if !conclusion.isEmpty, !valueText.contains(conclusion) {
                    valueText += "\n结论：\(conclusion)"
                }
                let sizeMM = ImagingFollowUpEnricher.primarySizeMillimeters(from: enrichedFinding)
                    ?? FindingSizeParser.maxMillimeters(in: valueText)
                if let sizeMM, sizeMM > 0,
                   !valueText.contains("mm"), !valueText.contains("cm"), !valueText.contains("毫米") {
                    valueText += "\n最大径约 \(String(format: "%.1f", sizeMM)) mm"
                }
                let encoded = ClinicalFindingTaxonomy.encodeTags(enrichedFinding.taxonomyTags)
                let metric = HealthMetric(
                    name: title,
                    value: sizeMM ?? 0,
                    valueText: valueText,
                    unit: sizeMM != nil ? "mm" : "",
                    referenceRange: enrichedFinding.category,
                    isAbnormal: enrichedFinding.isAbnormal,
                    date: batch.date,
                    category: "异常发现",
                    reportSection: ReportMetricCategory.sectionForFinding(category: enrichedFinding.category),
                    severityRank: enrichedFinding.severityRank,
                    assessmentNote: enrichedFinding.assessmentNote,
                    morphologyTag: encoded.morphology,
                    organSiteTag: encoded.organSite,
                    report: report
                )
                modelContext.insert(metric)
                report.metrics.append(metric)
            }

            saved.append(report)
        }

        try modelContext.save()
        try refreshRiskAnalysis(modelContext: modelContext)
        return saved
    }

    private struct VisitBatch {
        let date: Date
        var metrics: [ReportImporter.DraftMetric]
        var findings: [ReportImporter.DraftFinding]
    }

    private static func groupByVisitDate(
        metrics: [ReportImporter.DraftMetric],
        findings: [ReportImporter.DraftFinding],
        defaultDate: Date?
    ) -> [VisitBatch] {
        let fallback = Calendar.current.startOfDay(for: defaultDate ?? Date())
        var map: [Date: (metrics: [ReportImporter.DraftMetric], findings: [ReportImporter.DraftFinding])] = [:]

        func day(_ date: Date?) -> Date {
            Calendar.current.startOfDay(for: date ?? fallback)
        }

        for item in metrics {
            let key = day(item.visitDate)
            var bucket = map[key] ?? ([], [])
            bucket.metrics.append(item)
            map[key] = bucket
        }
        for item in findings {
            let key = day(item.visitDate)
            var bucket = map[key] ?? ([], [])
            bucket.findings.append(item)
            map[key] = bucket
        }

        if map.isEmpty {
            return [VisitBatch(date: fallback, metrics: metrics, findings: findings)]
        }

        return map.keys.sorted().map { date in
            let bucket = map[date] ?? ([], [])
            return VisitBatch(date: date, metrics: bucket.metrics, findings: bucket.findings)
        }
    }

    @MainActor
    static func refreshRiskAnalysis(modelContext: ModelContext) throws {
        let reports = try modelContext.fetch(FetchDescriptor<Report>())
        let verifiedMetrics = reports
            .filter(\.isVerified)
            .flatMap(\.metrics)

        let matches = ClinicalRiskEngine.analyze(metrics: verifiedMetrics)

        let existing = try modelContext.fetch(FetchDescriptor<RiskFlag>())
        for flag in existing where !flag.isResolved {
            modelContext.delete(flag)
        }

        for match in matches {
            let flag = RiskFlag(
                metricName: match.metricName,
                severity: match.severity,
                currentValue: match.currentValue,
                trendDescription: match.trend.rawValue,
                suggestedAction: match.suggestedAction,
                checkupMonths: match.checkupMonths ?? 3,
                department: match.department,
                seriesKey: match.seriesKey,
                isResolved: false
            )
            modelContext.insert(flag)
        }

        try modelContext.save()
    }

    static func importSummary(for report: Report) -> HealthProfileEngine.Summary {
        let metrics = report.metrics
        let risks = ClinicalRiskEngine.analyze(metrics: metrics)
        return HealthProfileEngine.buildSummary(from: metrics, risks: risks)
    }

    /// 删除单份报告及其关联指标，并重算风险提醒
    @MainActor
    static func deleteReport(_ report: Report, modelContext: ModelContext) throws {
        modelContext.delete(report)
        try modelContext.save()
        try refreshRiskAnalysis(modelContext: modelContext)
    }

    @MainActor
    static func setupCheckupPlan(
        from risk: RiskFlag,
        months: Int,
        lastExam: Date?,
        modelContext: ModelContext
    ) throws -> CheckupPlan {
        let anchor = lastExam ?? Date()
        let plans = try modelContext.fetch(FetchDescriptor<CheckupPlan>())
        if let existing = plans.first(where: { planMatchesRisk($0, risk: risk) }) {
            existing.frequencyInMonths = months
            existing.lastExamDate = anchor
            existing.department = risk.department
            existing.seriesKey = risk.seriesKey
            existing.metricName = risk.metricName
            existing.nextDueDate = Calendar.current.date(byAdding: .month, value: months, to: anchor) ?? anchor
            try modelContext.save()
            TodoService.scheduleCheckupReminders(for: existing)
            return existing
        }

        let plan = CheckupPlan(
            metricName: risk.metricName,
            department: risk.department,
            seriesKey: risk.seriesKey,
            frequencyInMonths: months,
            lastExamDate: anchor
        )
        modelContext.insert(plan)
        try modelContext.save()
        TodoService.scheduleCheckupReminders(for: plan)
        return plan
    }

    /// 更新复查频率或上次检查日期，并重排本地提醒
    @MainActor
    static func updateCheckupPlan(
        _ plan: CheckupPlan,
        frequencyMonths: Int,
        lastExamDate: Date? = nil,
        modelContext: ModelContext
    ) throws {
        plan.frequencyInMonths = frequencyMonths
        if let lastExamDate {
            plan.lastExamDate = lastExamDate
        }
        plan.nextDueDate = Calendar.current.date(
            byAdding: .month,
            value: frequencyMonths,
            to: plan.lastExamDate
        ) ?? plan.lastExamDate
        try modelContext.save()
        TodoService.scheduleCheckupReminders(for: plan)
    }

    /// 删除复查计划并取消通知
    @MainActor
    static func deleteCheckupPlan(_ plan: CheckupPlan, modelContext: ModelContext) throws {
        TodoService.cancelCheckupReminders(for: plan.id)
        modelContext.delete(plan)
        try modelContext.save()
    }

    static func planMatchesRisk(_ plan: CheckupPlan, risk: RiskFlag) -> Bool {
        if !risk.seriesKey.isEmpty, plan.seriesKey == risk.seriesKey { return true }
        return plan.metricName == risk.metricName
    }
}

/// 从主检建议 / 总结生成结构化复查随访建议
/// @author jiali.qiu
enum FollowUpRecommendationEngine {

    struct Item: Identifiable, Equatable {
        let id: String
        let department: String
        let topics: [String]
        let action: String

        var line: String {
            let topicText = topics.joined(separator: "、")
            if action.isEmpty { return "\(department)：\(topicText)" }
            return "\(department)：\(topicText) — \(action)"
        }

        /// 校对页展示用（不含重复科室名）
        var bodyText: String {
            let topicText = topics.joined(separator: "、")
            if action.isEmpty { return topicText }
            if topicText.isEmpty { return action }
            return "\(topicText) — \(action)"
        }

        var hasBody: Bool {
            bodyText.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2
        }
    }

    /// 从导入草稿生成复查建议（主检 recommendations + 总结 assessmentSummary）
    static func build(from draft: ReportImporter.ImportDraft) -> [Item] {
        build(
            recommendations: draft.recommendations,
            assessmentSummary: draft.assessmentSummary,
            abnormalFindingTitles: draft.findings.filter(\.isAbnormal).map(\.title),
            abnormalMetricNames: draft.metrics.filter(\.isAbnormal).map(\.name)
        )
    }

    static func build(
        recommendations: [String],
        assessmentSummary: String,
        abnormalFindingTitles: [String] = [],
        abnormalMetricNames: [String] = []
    ) -> [Item] {
        var buckets: [String: (topics: [String], action: String)] = [:]

        for raw in recommendations {
            let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard line.count >= 4 else { continue }
            let (topic, action) = splitTopicAction(line)
            let dept = inferDepartment(topic: topic, action: action)
            merge(into: &buckets, department: dept, topic: topic, action: action)
        }

        let summaryDepartments = extractDepartments(from: assessmentSummary)
        if !summaryDepartments.isEmpty {
            for dept in summaryDepartments where buckets[dept] == nil {
                buckets[dept] = (topics: ["本次体检异常项"], action: "按主检建议随访及治疗")
            }
        }

        attachOrphanAbnormals(
            into: &buckets,
            findings: abnormalFindingTitles,
            metrics: abnormalMetricNames
        )

        let order = ["胸外科", "肝胆外科", "内分泌科", "妇科", "乳腺外科", "泌尿科", "消化内科", "心血管内科", "其他"]
        return buckets.map { dept, value in
            Item(
                id: dept,
                department: dept,
                topics: Array(Set(value.topics)).sorted(),
                action: value.action
            )
        }
        .filter { $0.hasBody }
        .sorted {
            let li = order.firstIndex(of: $0.department) ?? order.count
            let ri = order.firstIndex(of: $1.department) ?? order.count
            if li != ri { return li < ri }
            return $0.department < $1.department
        }
    }

    static func formattedLines(from items: [Item]) -> [String] {
        items.map(\.line)
    }

    // MARK: - Private

    private static func splitTopicAction(_ line: String) -> (topic: String, action: String) {
        if let range = line.range(of: "：") ?? line.range(of: ":") {
            let topic = String(line[..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
            let action = String(line[line.index(after: range.lowerBound)...]).trimmingCharacters(in: .whitespaces)
            return (topic, action)
        }
        return (line, "")
    }

    private static func inferDepartment(topic: String, action: String) -> String {
        let blob = RiskAnalyzer.normalize(topic + action)
        if blob.contains("乳腺") || blob.contains("小叶增生") { return "乳腺外科" }
        if blob.contains("宫颈") || blob.contains("阴道") || blob.contains("子宫") || blob.contains("妇科") {
            return "妇科"
        }
        if blob.contains("脂") || blob.contains("胆固醇") || blob.contains("ldl") || blob.contains("内分泌") {
            return "内分泌科"
        }
        if blob.contains("肺") || blob.contains("磨玻璃") || blob.contains("胸部") || blob.contains("ct") {
            return "胸外科"
        }
        if blob.contains("尿") || blob.contains("肾") { return "泌尿科" }
        if blob.contains("肝") || blob.contains("胆") || blob.contains("fnh") || blob.contains("血管瘤") {
            return "肝胆外科"
        }
        if blob.contains("心") || blob.contains("血压") { return "心血管内科" }
        return "其他"
    }

    private static func extractDepartments(from summary: String) -> [String] {
        let text = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return [] }
        let known = [
            "胸外科", "肝胆外科", "内分泌科", "妇科", "乳腺外科",
            "泌尿科", "消化内科", "心血管内科", "甲状腺外科", "普外科"
        ]
        return known.filter { text.contains($0) }
    }

    private static func merge(
        into buckets: inout [String: (topics: [String], action: String)],
        department: String,
        topic: String,
        action: String
    ) {
        var entry = buckets[department] ?? (topics: [], action: "")
        if !topic.isEmpty, !entry.topics.contains(topic) {
            entry.topics.append(topic)
        }
        if !action.isEmpty {
            entry.action = entry.action.isEmpty ? action : entry.action
        }
        buckets[department] = entry
    }

    private static func attachOrphanAbnormals(
        into buckets: inout [String: (topics: [String], action: String)],
        findings: [String],
        metrics: [String]
    ) {
        for title in findings {
            let dept = inferDepartment(topic: title, action: "")
            if buckets[dept] == nil {
                buckets[dept] = (topics: [title], action: "遵医嘱复查")
            }
        }
        for name in metrics {
            let dept = inferDepartment(topic: name, action: "")
            guard buckets[dept] == nil else { continue }
            buckets[dept] = (topics: [name], action: "遵医嘱复查")
        }
    }
}
