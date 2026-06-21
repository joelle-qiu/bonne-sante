import Foundation

/// 综合健康摘要（纯函数）
/// @author jiali.qiu
enum HealthProfileEngine {

    /// 随访动作优先级：复查/治疗 > 定期随访
    enum FollowUpPriority: Int, Comparable {
        case recheckOrTreat = 0
        case routineFollowUp = 1

        static func < (lhs: FollowUpPriority, rhs: FollowUpPriority) -> Bool {
            lhs.rawValue < rhs.rawValue
        }

        var sectionTitle: String {
            switch self {
            case .recheckOrTreat: return "建议复查 / 治疗"
            case .routineFollowUp: return "定期随访"
            }
        }
    }

    struct AbnormalDisplayItem: Identifiable, Equatable {
        let id: String
        let name: String
        let valueSummary: String
        let trendArrow: String?
        let actionHint: String
        let department: String
        let priority: FollowUpPriority
        let severityRank: Int

        var compactLine: String {
            let value = trendArrow.map { "\(valueSummary) \($0)" } ?? valueSummary
            let hint = Self.deduplicatedActionHint(actionHint, valueSummary: valueSummary)
            if hint.isEmpty { return "\(name) \(value)" }
            return "\(name) \(value) — \(hint)"
        }

        /// 去掉与 valueSummary 重复的建议句（避免「结论；结论」）
        fileprivate static func deduplicatedActionHint(_ hint: String, valueSummary: String) -> String {
            let trimmed = hint.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return "" }
            let parts = trimmed
                .split(whereSeparator: { $0 == ";" || $0 == "；" })
                .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { $0.count >= 4 }
            let unique = dedupeSimilarFragments(parts + [valueSummary])
                .filter { part in
                    let np = RiskAnalyzer.normalize(part)
                    let nv = RiskAnalyzer.normalize(valueSummary)
                    return !nv.contains(np) && !np.contains(nv) || part.count > nv.count + 8
                }
            return unique.joined(separator: "；")
        }

        fileprivate static func dedupeSimilarFragments(_ parts: [String]) -> [String] {
            var result: [String] = []
            for part in parts {
                let norm = RiskAnalyzer.normalize(part)
                guard norm.count >= 4 else { continue }
                if result.contains(where: { fragmentsSimilar(norm, RiskAnalyzer.normalize($0)) }) { continue }
                result.append(part)
            }
            return result
        }

        fileprivate static func fragmentsSimilar(_ a: String, _ b: String) -> Bool {
            if a.isEmpty || b.isEmpty { return false }
            if a == b { return true }
            if a.count >= 8, b.count >= 8, (a.contains(b) || b.contains(a)) { return true }
            return false
        }
    }

    struct AbnormalDepartmentGroup: Identifiable, Equatable {
        let id: String
        let department: String
        let items: [AbnormalDisplayItem]
    }

    struct AbnormalPriorityGroup: Identifiable, Equatable {
        let id: FollowUpPriority
        let title: String
        let departments: [AbnormalDepartmentGroup]
    }

    struct Summary: Sendable {
        let headline: String
        /// 扁平列表（供 AI 顾问等旧接口）
        let abnormalItems: [String]
        /// 按优先级 → 科目分组（供摘要页展示）
        let abnormalGroups: [AbnormalPriorityGroup]
        let activeRiskCount: Int
        let highRiskCount: Int
        let dietaryNotes: [String]
        let proteinFloorGrams: Double?
    }

    /// 首页「健康动态」应展示的优先级最高复查提醒（与健康摘要排序一致）
    static func topPriorityFollowUp(from summary: Summary?) -> AbnormalDisplayItem? {
        guard let summary else { return nil }
        for group in summary.abnormalGroups {
            for department in group.departments {
                if let item = department.items.first { return item }
            }
        }
        return nil
    }

    /// 主线程快照，避免后台任务触碰 SwiftData `Report.metrics` 关系
    struct ReportSummarySnapshot: Sendable {
        let metricInputs: [MetricInput]
        let recommendationTexts: [String]
        let reportCount: Int
    }

    @MainActor
    static func snapshotFromReports(_ reports: [Report]) -> ReportSummarySnapshot {
        let inputs = reports.flatMap { report in
            report.metrics.map { MetricInput(from: $0) }
        }
        let recommendationTexts = reports
            .map(\.recommendationsText)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        return ReportSummarySnapshot(
            metricInputs: inputs,
            recommendationTexts: recommendationTexts,
            reportCount: reports.count
        )
    }

    struct MetricInput: Sendable {
        let name: String
        let value: Double
        let valueText: String
        let unit: String
        let referenceRange: String
        let reportSection: String
        let category: String
        let isAbnormal: Bool
        let severityRank: Int
        let assessmentNote: String
        let date: Date
        let morphologyTag: String
        let organSiteTag: String

        init(from metric: HealthMetric) {
            name = metric.name
            value = metric.value
            valueText = metric.valueText
            unit = metric.unit
            referenceRange = metric.referenceRange
            reportSection = metric.reportSection
            category = metric.category
            isAbnormal = metric.isAbnormal
            severityRank = metric.severityRank
            assessmentNote = metric.assessmentNote
            date = metric.date
            morphologyTag = metric.morphologyTag
            organSiteTag = metric.organSiteTag
        }

        init(from snapshot: RiskAnalyzer.MetricSnapshot, reportSection: String = "") {
            name = snapshot.name
            value = snapshot.value
            valueText = snapshot.valueText
            unit = snapshot.unit
            referenceRange = ""
            category = "检验"
            self.reportSection = reportSection.isEmpty
                ? ReportMetricCategory.inferSection(name: snapshot.name, valueText: snapshot.valueText)
                : reportSection
            isAbnormal = snapshot.isAbnormal
            severityRank = snapshot.severityRank
            assessmentNote = snapshot.assessmentNote
            date = snapshot.date
            morphologyTag = ""
            organSiteTag = ""
        }

        var taxonomyTags: ClinicalFindingTaxonomy.Tags {
            let stored = ClinicalFindingTaxonomy.decodeStored(
                morphologyTag: morphologyTag,
                organSiteTag: organSiteTag
            )
            if !stored.isEmpty { return stored }
            return ClinicalFindingTaxonomy.inferFromText(name + valueText + assessmentNote)
        }

        var isClinicalFinding: Bool {
            category == "异常发现" || reportSection == "影像检查" || reportSection == "心电图"
        }
    }

    static func buildSummary(
        metrics: [RiskAnalyzer.MetricSnapshot],
        risks: [RiskAnalyzer.RuleMatch]
    ) -> Summary {
        let inputs = metrics.map { MetricInput(from: $0) }
        return buildSummary(metricInputs: inputs, risks: risks)
    }

    static func buildSummary(from metrics: [HealthMetric], risks: [RiskAnalyzer.RuleMatch]) -> Summary {
        let inputs = metrics.map { MetricInput(from: $0) }
        return buildSummary(metricInputs: inputs, risks: risks, dedupeAbnormals: false)
    }

    /// 跨报告健康摘要（后台计算，避免阻塞 UI）
    @MainActor
    static func buildSummaryAsync(from reports: [Report]) async -> Summary {
        await buildSummaryAsync(snapshot: snapshotFromReports(reports))
    }

    static func buildSummaryAsync(snapshot: ReportSummarySnapshot) async -> Summary {
        let inputs = snapshot.metricInputs
        let recommendationTexts = snapshot.recommendationTexts
        let reportCount = snapshot.reportCount
        return await Task.detached(priority: .userInitiated) {
            buildSummary(
                metricInputs: inputs,
                risks: analyzeRisk(from: inputs),
                dedupeAbnormals: true,
                reportCount: reportCount,
                recommendationTexts: recommendationTexts
            )
        }.value
    }

    private static func analyzeRisk(from inputs: [MetricInput]) -> [RiskAnalyzer.RuleMatch] {
        ClinicalRiskEngine.analyze(inputs: inputs)
    }

    /// 与异常指标 dedupe 使用同一序列 key
    static func riskSeriesKey(for metric: HealthMetric) -> String {
        riskSeriesKey(for: MetricInput(from: metric))
    }

    static func riskSeriesKey(for input: MetricInput) -> String {
        dedupeKey(for: input)
    }

    static func metricInputs(from metrics: [HealthMetric]) -> [MetricInput] {
        metrics.map { MetricInput(from: $0) }
    }

    static func isEffectiveAbnormal(_ metric: MetricInput) -> Bool {
        isEffectiveAbnormalMetric(metric)
    }

    static func abnormalDisplayItem(for metric: MetricInput) -> AbnormalDisplayItem {
        buildDisplayItem(from: metric)
    }

    static func compactRiskValue(for metric: MetricInput) -> String {
        compactValueSummary(metric)
    }

    private static func buildSummary(
        metricInputs: [MetricInput],
        risks: [RiskAnalyzer.RuleMatch]
    ) -> Summary {
        buildSummary(metricInputs: metricInputs, risks: risks, dedupeAbnormals: false, reportCount: 1)
    }

    private static func buildSummary(
        metricInputs: [MetricInput],
        risks: [RiskAnalyzer.RuleMatch],
        dedupeAbnormals: Bool,
        reportCount: Int = 1,
        recommendationTexts: [String] = []
    ) -> Summary {
        let abnormalSource = dedupeAbnormals ? latestAbnormalInputs(metricInputs) : metricInputs
        var displayItems = buildAbnormalDisplayItems(from: abnormalSource)
        displayItems.append(contentsOf: supplementFromRecommendations(recommendationTexts, existing: displayItems))
        displayItems = collapseDuplicateDisplayItems(displayItems)
        displayItems.sort {
            if $0.priority != $1.priority { return $0.priority < $1.priority }
            if $0.severityRank != $1.severityRank { return $0.severityRank > $1.severityRank }
            if $0.department != $1.department { return $0.department < $1.department }
            return $0.name < $1.name
        }
        let groups = groupAbnormalItems(displayItems)
        let flatLines = displayItems.map(\.compactLine)

        let highCount = risks.filter { $0.severity == .high }.count
        var headline: String
        if risks.isEmpty && displayItems.isEmpty {
            headline = "暂无需要特别关注的异常指标"
        } else if highCount > 0 {
            headline = "发现 \(highCount) 项需优先关注的风险、共 \(risks.count) 项科室提醒，请遵医嘱复查"
        } else if risks.isEmpty && !displayItems.isEmpty {
            headline = "最新报告仍有 \(displayItems.count) 项异常，请按科目与建议安排随访"
        } else {
            headline = "发现 \(risks.count) 项健康提醒，建议按建议安排复查"
        }
        if dedupeAbnormals, reportCount > 1 {
            headline += "（已汇总 \(reportCount) 份报告）"
        }

        var dietary: [String] = []
        if risks.contains(where: { RiskAnalyzer.normalize($0.metricName).contains("尿酸") }) {
            dietary.append("尿酸偏高：建议低嘌呤饮食，适量饮水")
        }
        if risks.contains(where: { RiskAnalyzer.normalize($0.metricName).contains("血糖") }) {
            dietary.append("血糖偏高：控制精制碳水，均衡膳食")
        }

        let proteinFloor = proteinFloorSuggestion(from: risks)

        return Summary(
            headline: headline,
            abnormalItems: Array(flatLines.prefix(12)),
            abnormalGroups: groups,
            activeRiskCount: risks.count,
            highRiskCount: highCount,
            dietaryNotes: dietary,
            proteinFloorGrams: proteinFloor
        )
    }

    // MARK: - 异常项分组与文案

    /// 跨报告摘要：每种指标只保留最近一次异常结果
    private static func latestAbnormalInputs(_ metrics: [MetricInput]) -> [MetricInput] {
        var byKey: [String: MetricInput] = [:]
        for metric in metrics where isEffectiveAbnormal(metric) {
            let key = dedupeKey(for: metric)
            if let existing = byKey[key], existing.date >= metric.date { continue }
            byKey[key] = metric
        }
        return Array(byKey.values)
    }

    private static func dedupeKey(for metric: MetricInput) -> String {
        if metric.isClinicalFinding {
            let stub = HealthMetric(
                name: metric.name,
                value: metric.value,
                valueText: metric.valueText,
                unit: metric.unit,
                isAbnormal: metric.isAbnormal,
                date: metric.date,
                category: metric.category,
                reportSection: metric.reportSection,
                severityRank: metric.severityRank,
                assessmentNote: metric.assessmentNote,
                morphologyTag: metric.morphologyTag,
                organSiteTag: metric.organSiteTag
            )
            if let seriesKey = FindingNameCanonicalizer.trendSeriesKey(for: stub) {
                return seriesKey
            }
            let tags = metric.taxonomyTags
            if tags.organSite != .other || tags.morphology != .other {
                return "finding.\(tags.organSite.rawValue).\(tags.morphology.rawValue)"
            }
            return "finding." + RiskAnalyzer.normalize(metric.name)
        }
        return MetricNameCanonicalizer.canonicalKey(for: metric.name)
    }

    /// 同名同科室条目合并为一条（保留严重度更高 / 文案更完整者）
    private static func collapseDuplicateDisplayItems(_ items: [AbnormalDisplayItem]) -> [AbnormalDisplayItem] {
        var byKey: [String: AbnormalDisplayItem] = [:]
        for item in items {
            let key = item.department + "|" + item.name
            if let existing = byKey[key] {
                byKey[key] = preferDisplayItem(existing, item)
            } else {
                byKey[key] = item
            }
        }
        return Array(byKey.values)
    }

    private static func preferDisplayItem(
        _ left: AbnormalDisplayItem,
        _ right: AbnormalDisplayItem
    ) -> AbnormalDisplayItem {
        if left.severityRank != right.severityRank {
            return left.severityRank >= right.severityRank ? left : right
        }
        if left.compactLine.count >= right.compactLine.count { return left }
        return right
    }

    /// 主检建议中尚未入库为 findings 的条目，补进摘要（兜底）
    private static func supplementFromRecommendations(
        _ texts: [String],
        existing: [AbnormalDisplayItem]
    ) -> [AbnormalDisplayItem] {
        var items: [AbnormalDisplayItem] = []
        for text in texts {
            for line in text.components(separatedBy: .newlines) {
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard trimmed.count >= 6 else { continue }
                guard let parsed = parseRecommendationLine(trimmed) else { continue }
                let inferred = ClinicalFindingTaxonomy.inferFromText(parsed.topic + parsed.action)
                if topicAlreadyCovered(parsed.topic, tags: inferred, in: existing + items) { continue }
                let dept = ClinicalFindingTaxonomy.clinicalDepartment(
                    tags: inferred,
                    name: parsed.topic,
                    assessmentNote: parsed.action
                )
                let displayName = inferred.briefLabel.isEmpty
                    ? simplifiedName(parsed.topic)
                    : inferred.briefLabel
                let priority = inferFollowUpPriority(assessmentNote: parsed.action, severityRank: 2)
                items.append(AbnormalDisplayItem(
                    id: "rec|\(dept)|\(displayName)",
                    name: displayName,
                    valueSummary: parsed.detail,
                    trendArrow: nil,
                    actionHint: extractActionHint(from: parsed.action, metricName: parsed.topic, valueText: ""),
                    department: dept,
                    priority: priority,
                    severityRank: priority == .recheckOrTreat ? 2 : 1
                ))
            }
        }
        return items
    }

    private static func parseRecommendationLine(_ line: String) -> (topic: String, detail: String, action: String)? {
        let separators = ["：", ":"]
        for sep in separators {
            guard let range = line.range(of: sep) else { continue }
            let topic = String(line[..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
            let action = String(line[line.index(after: range.lowerBound)...]).trimmingCharacters(in: .whitespaces)
            guard topic.count >= 2, action.count >= 4 else { continue }
            let detail = topicBriefDetail(topic)
            return (topic, detail, action)
        }
        return nil
    }

    private static func topicBriefDetail(_ topic: String) -> String {
        if topic.count <= 20 { return topic }
        return String(topic.prefix(20))
    }

    private static func topicAlreadyCovered(
        _ topic: String,
        tags: ClinicalFindingTaxonomy.Tags,
        in items: [AbnormalDisplayItem]
    ) -> Bool {
        if items.contains(where: { topicsOverlap(topic, $0.name + $0.valueSummary + $0.actionHint) }) {
            return true
        }
        if tags.organSite != .other {
            let organLabel = tags.organSite.displayLabel
            return items.contains { $0.name.contains(organLabel) || $0.valueSummary.contains(organLabel) }
        }
        if tags.morphology != .other {
            let morphLabel = tags.morphology.displayLabel
            return items.contains { $0.name.contains(morphLabel) || $0.valueSummary.contains(morphLabel) }
        }
        return false
    }

    private static func topicsOverlap(_ a: String, _ b: String) -> Bool {
        let na = RiskAnalyzer.normalize(a)
        let nb = RiskAnalyzer.normalize(b)
        if na.isEmpty || nb.isEmpty { return false }
        if na.contains(nb) || nb.contains(na) { return true }
        let organs = ["肝", "甲状腺", "乳腺", "子宫", "附件", "颈椎", "宫颈", "心", "肺", "肾", "牙"]
        return organs.contains { na.contains($0) && nb.contains($0) }
    }

    private static let clinicalConcernKeywords = [
        "血管瘤", "囊肿", "纳氏", "结节", "增生", "曲度", "不齐", "结石", "低回声",
        "欠均匀", "可能", "占位", "肌瘤", "糜烂", "阳性", "增高"
    ]

    private static func buildAbnormalDisplayItems(from metrics: [MetricInput]) -> [AbnormalDisplayItem] {
        metrics
            .filter { isEffectiveAbnormal($0) }
            .map { buildDisplayItem(from: $0) }
            .sorted {
                if $0.priority != $1.priority { return $0.priority < $1.priority }
                if $0.severityRank != $1.severityRank { return $0.severityRank > $1.severityRank }
                if $0.department != $1.department { return $0.department < $1.department }
                return $0.name < $1.name
            }
    }

    private static func groupAbnormalItems(_ items: [AbnormalDisplayItem]) -> [AbnormalPriorityGroup] {
        let priorityOrder: [FollowUpPriority] = [.recheckOrTreat, .routineFollowUp]
        return priorityOrder.compactMap { priority in
            let tierItems = items.filter { $0.priority == priority }
            guard !tierItems.isEmpty else { return nil }

            var deptBuckets: [String: [AbnormalDisplayItem]] = [:]
            for item in tierItems {
                deptBuckets[item.department, default: []].append(item)
            }
            let deptOrder = [
                "胸外科", "肝胆外科", "内分泌科", "妇科", "影像科", "泌尿科", "骨科康复", "心血管科",
                "消化内科", "口腔科", "检验科", "肿瘤科", "其他"
            ]
            let departments = deptOrder.compactMap { dept -> AbnormalDepartmentGroup? in
                guard let list = deptBuckets[dept], !list.isEmpty else { return nil }
                return AbnormalDepartmentGroup(
                    id: "\(priority.rawValue)-\(dept)",
                    department: dept,
                    items: list.sorted { $0.severityRank > $1.severityRank }
                )
            } + deptBuckets.keys
                .filter { !deptOrder.contains($0) }
                .sorted()
                .compactMap { dept -> AbnormalDepartmentGroup? in
                    guard let list = deptBuckets[dept], !list.isEmpty else { return nil }
                    return AbnormalDepartmentGroup(
                        id: "\(priority.rawValue)-\(dept)",
                        department: dept,
                        items: list.sorted { $0.severityRank > $1.severityRank }
                    )
                }

            return AbnormalPriorityGroup(
                id: priority,
                title: priority.sectionTitle,
                departments: departments
            )
        }
    }

    private static func buildDisplayItem(from metric: MetricInput) -> AbnormalDisplayItem {
        let section = metric.reportSection.isEmpty
            ? ReportMetricCategory.inferSection(name: metric.name, valueText: metric.valueText)
            : metric.reportSection
        let department = ClinicalFindingTaxonomy.clinicalDepartment(
            tags: metric.taxonomyTags,
            section: section,
            name: metric.name,
            assessmentNote: metric.assessmentNote
        )
        let priority = inferFollowUpPriority(
            assessmentNote: metric.assessmentNote,
            severityRank: metric.severityRank
        )
        let name = displayName(for: metric)
        let valueSummary = compactValueSummary(metric)
        let trendArrow = ReportMetricNormalizer.inferTrendArrow(
            value: metric.value,
            referenceRange: metric.referenceRange,
            lineHint: metric.valueText + metric.assessmentNote
        )
        let actionHint = extractActionHint(
            from: metric.assessmentNote,
            metricName: name,
            valueText: valueSummary
        )

        return AbnormalDisplayItem(
            id: "\(department)|\(name)|\(metric.valueText)",
            name: name,
            valueSummary: valueSummary,
            trendArrow: trendArrow,
            actionHint: actionHint,
            department: department,
            priority: priority,
            severityRank: metric.severityRank
        )
    }

    private static func isEffectiveAbnormalMetric(_ metric: MetricInput) -> Bool {
        let blob = RiskAnalyzer.normalize(metric.name + metric.valueText + metric.assessmentNote)

        if metric.isClinicalFinding {
            let tags = metric.taxonomyTags
            if tags.morphology == .normal { return false }
            if ClinicalFindingTaxonomy.isClinicallySignificant(
                tags: tags,
                isAbnormal: metric.isAbnormal,
                severityRank: metric.severityRank
            ) {
                return true
            }
            if blob.contains("未见明显异常"), !clinicalConcernKeywords.contains(where: { blob.contains($0) }) {
                return false
            }
            if !metric.isAbnormal, metric.severityRank == 0,
               !clinicalConcernKeywords.contains(where: { blob.contains($0) }) {
                return false
            }
            return true
        }

        guard metric.isAbnormal else { return false }
        let normalHints = ["正常", "未见明显异常", "阴性", "未查见", "在正常范围"]
        if normalHints.contains(where: { blob.contains($0) }) {
            let abnormalHints = ["异常", "升高", "偏低", "阳性", "超标", "炎症", "结节", "肌瘤", "+"]
                + clinicalConcernKeywords
            if !abnormalHints.contains(where: { blob.contains($0) }) { return false }
        }
        return true
    }

    private static func inferFollowUpPriority(assessmentNote: String, severityRank: Int) -> FollowUpPriority {
        let note = RiskAnalyzer.normalize(assessmentNote)
        if note.contains("复查") || note.contains("治疗") || note.contains("就医")
            || note.contains("专科") || note.contains("干预") || note.contains("炎症")
            || note.contains("阳性") || note.contains("感染") {
            return .recheckOrTreat
        }
        if note.contains("随访") || note.contains("定期") || note.contains("生活方式")
            || note.contains("调整") || note.contains("良性") || note.contains("相仿")
            || note.contains("ct") || note.contains("增强") {
            return .routineFollowUp
        }
        if note.contains("磨玻璃") || note.contains("结节") || note.contains("血管瘤") || note.contains("fnh") {
            return severityRank >= 2 ? .routineFollowUp : .recheckOrTreat
        }
        return severityRank >= 3 ? .recheckOrTreat : .routineFollowUp
    }

    private static func displayName(for metric: MetricInput) -> String {
        let tags = metric.taxonomyTags
        if metric.isClinicalFinding, !tags.briefLabel.isEmpty {
            return tags.briefLabel
        }
        return simplifiedName(metric.name)
    }

    private static func simplifiedName(_ raw: String) -> String {
        let pro = ReportMetricCategory.professionalPanelName(raw)
        if pro != raw, pro.count <= 12 { return pro }
        var name = raw
            .replacingOccurrences(of: "（", with: "(")
            .replacingOccurrences(of: "）", with: ")")
        if let paren = name.firstIndex(of: "(") {
            name = String(name[..<paren]).trimmingCharacters(in: .whitespaces)
        }
        if name.count > 14 {
            return String(name.prefix(14))
        }
        return name
    }

    private static func compactValueSummary(_ metric: MetricInput) -> String {
        if metric.isClinicalFinding {
            return clinicalBriefSummary(metric)
        }
        let text = metric.valueText.trimmingCharacters(in: .whitespaces)
        let base: String
        if text.count <= 24 {
            base = text
        } else         if metric.value > 0, !metric.unit.isEmpty {
            base = String(format: "%.2g %@", metric.value, metric.unit)
        } else {
            base = String(text.prefix(24))
        }
        return base
    }

    private static func clinicalBriefSummary(_ metric: MetricInput) -> String {
        let text = metric.valueText.trimmingCharacters(in: .whitespaces)
        var sizePrefix: String?
        if metric.value > 0 {
            if metric.unit == "mm" || metric.unit.isEmpty, metric.value < 500 {
                sizePrefix = String(format: "%.1f mm", metric.value)
            } else if !metric.unit.isEmpty {
                sizePrefix = String(format: "%.2g %@", metric.value, metric.unit)
            }
        }
        if let range = text.range(of: "结论：") {
            let conclusion = String(text[range.upperBound...]).trimmingCharacters(in: .whitespaces)
            if !conclusion.isEmpty {
                let body = String(conclusion.prefix(28))
                if let sizePrefix { return "\(sizePrefix)；\(body)" }
                return body
            }
        }
        var body = text
        if body.hasPrefix(metric.name) {
            body = body.dropFirst(metric.name.count).trimmingCharacters(in: .whitespaces)
            if body.hasPrefix("：") || body.hasPrefix(":") {
                body = String(body.dropFirst()).trimmingCharacters(in: .whitespaces)
            }
        }
        if let sizePrefix, body.count > 28 || body.isEmpty {
            return sizePrefix
        }
        if body.count <= 28 { return body.isEmpty ? (sizePrefix ?? "见报告描述") : body }
        if let sizePrefix { return "\(sizePrefix)；\(String(body.prefix(20)))" }
        return String(body.prefix(28))
    }

    private static func extractActionHint(
        from assessmentNote: String,
        metricName: String,
        valueText: String
    ) -> String {
        var note = assessmentNote.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !note.isEmpty else { return "" }

        note = stripRedundantLead(note, name: metricName, valueText: valueText)
        note = AbnormalDisplayItem.dedupeSimilarFragments(
            note.split(whereSeparator: { $0 == ";" || $0 == "；" })
                .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
        ).joined(separator: "；")

        if let range = note.range(of: "建议") {
            return truncateAtPunctuation(String(note[range.lowerBound...]), maxLength: 44)
        }
        if note.hasPrefix("结论：") {
            let body = String(note.dropFirst(3)).trimmingCharacters(in: .whitespaces)
            return truncateAtPunctuation(body, maxLength: 44)
        }
        return truncateAtPunctuation(note, maxLength: 44)
    }

    private static func stripRedundantLead(_ note: String, name: String, valueText: String) -> String {
        var s = note
        let plainValue = valueText
            .replacingOccurrences(of: " ↑", with: "")
            .replacingOccurrences(of: " ↓", with: "")
            .trimmingCharacters(in: .whitespaces)

        if s.hasPrefix(name) {
            s = String(s.dropFirst(name.count)).trimmingCharacters(in: .whitespaces)
            if s.hasPrefix("：") || s.hasPrefix(":") {
                s = String(s.dropFirst()).trimmingCharacters(in: .whitespaces)
            }
        }
        if !plainValue.isEmpty, s.hasPrefix(plainValue) {
            s = String(s.dropFirst(plainValue.count)).trimmingCharacters(in: .whitespaces)
            if s.hasPrefix("，") || s.hasPrefix(",") {
                s = String(s.dropFirst()).trimmingCharacters(in: .whitespaces)
            }
        }
        return s
    }

    /// 在标点处截断，避免「可能饮食或」这类半句话
    private static func truncateAtPunctuation(_ text: String, maxLength: Int) -> String {
        if text.count <= maxLength { return text }
        let slice = String(text.prefix(maxLength))
        let punct: [Character] = ["。", "；", "，", "、"]
        if let idx = slice.lastIndex(where: { punct.contains($0) }), slice.distance(from: slice.startIndex, to: idx) >= 10 {
            return String(slice[..<idx]).trimmingCharacters(in: .whitespaces)
        }
        return slice.trimmingCharacters(in: .whitespaces) + "…"
    }

    static func snapshots(from metrics: [HealthMetric]) -> [RiskAnalyzer.MetricSnapshot] {
        metrics.map {
            RiskAnalyzer.MetricSnapshot(
                name: $0.name,
                value: $0.value,
                valueText: $0.valueText,
                unit: $0.unit,
                date: $0.date,
                isAbnormal: $0.isAbnormal,
                severityRank: $0.severityRank,
                assessmentNote: $0.assessmentNote
            )
        }
    }

    private static func proteinFloorSuggestion(from risks: [RiskAnalyzer.RuleMatch]) -> Double? {
        if risks.contains(where: {
            let k = RiskAnalyzer.normalize($0.metricName)
            return k.contains("尿酸") || k.contains("肾")
        }) {
            return 1.2
        }
        return nil
    }
}
