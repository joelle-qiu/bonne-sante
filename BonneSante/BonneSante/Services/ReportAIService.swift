import Foundation

/// 使用 DeepSeek 将 OCR 纯文本结构化为指标 / 异常发现 / 建议（不上传原始图片）
/// @author jiali.qiu
enum ReportAIService {

    enum ParseSource {
        /// 本地 OCR 结果，严格过滤误报
        case ocr
        /// DeepSeek 网页整理后粘贴，信任度更高，过滤从宽
        case deepSeekPaste
    }

    struct MetricJSON: Decodable {
        let name: String?
        let title: String?
        let panel: String?
        let items: [MetricJSON]?
        let value: Double?
        let valueText: String?
        let detail: String?
        let unit: String?
        let referenceRange: String?
        let isAbnormal: Bool?
        let visitDate: String?
        let section: String?
        let severityRank: Int?
        let assessmentNote: String?

        var resolvedName: String {
            (name ?? title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        }

        var resolvedPanel: String {
            (panel ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        }

        /// DeepSeek 已输出 panel + items[] 嵌套结构
        var hasStructuredItems: Bool {
            guard let items, !items.isEmpty else { return false }
            return items.contains { $0.resolvedName.count >= 2 }
        }

        var resolvedValueText: String {
            if let text = valueText?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
                return text
            }
            if let text = detail?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
                return text
            }
            if let value { return String(value) }
            return ""
        }
    }

    struct FindingJSON: Decodable {
        let category: String?
        let title: String
        let detail: String?
        let conclusion: String?
        let isAbnormal: Bool?
        let visitDate: String?
        let severityRank: Int?
        let assessmentNote: String?
        let morphology: String?
        let organSite: String?
        let morphologyTags: [String]?
        /// 趋势主径（mm），肺结节写磨玻璃主结节长径，肝血管瘤写较大灶最大径
        let primarySizeMm: Double?
        /// 次要灶（mm），如 FNH 最大径或微小结节范围上限
        let secondarySizeMm: Double?
        /// 肺结节 CT 值（Hu）
        let ctValueHu: Int?
    }

    struct StructuredExtraction {
        var metrics: [ReportImporter.DraftMetric]
        var findings: [ReportImporter.DraftFinding]
        var recommendations: [String]
        var examDate: Date?
        var assessmentSummary: String = ""

        var isEmpty: Bool {
            metrics.isEmpty && findings.isEmpty && recommendations.isEmpty
        }
    }

    struct TextSections {
        var summary: String
        var labTables: String
        var imaging: String
        var fullText: String
    }

    struct ResponseEnvelope: Decodable {
        let examDate: String?
        let metrics: [MetricJSON]?
        let findings: [FindingJSON]?
        let recommendations: [String]?
        let assessmentNote: String?
    }

    /// 分区 OCR 文本 → 结构化结果
    static func extractStructuredReport(from sections: TextSections) async throws -> StructuredExtraction {
        guard APIKeyManager.isDeepSeekConfigured, let apiKey = APIKeyManager.deepSeekAPIKey else {
            return StructuredExtraction(metrics: [], findings: [], recommendations: [], examDate: nil)
        }

        let sanitized = sanitizeForCloud(sections.fullText)
        guard sanitized.count >= 20 else {
            return StructuredExtraction(metrics: [], findings: [], recommendations: [], examDate: nil)
        }

        let system = ReportDeepSeekPastePrompt.ocrStructuredSystemPrompt

        var userContent = "OCR 文本如下：\n\(sanitized.prefix(14000))\n"
        if !sections.summary.isEmpty {
            userContent += "\n【异常汇总段】\n\(sanitizeForCloud(sections.summary).prefix(3000))\n"
        }
        if !sections.labTables.isEmpty {
            userContent += "\n【检验表段】\n\(sanitizeForCloud(sections.labTables).prefix(6000))\n"
        }
        if !sections.imaging.isEmpty {
            userContent += "\n【影像段】\n\(sanitizeForCloud(sections.imaging).prefix(3000))\n"
        }

        let body: [String: Any] = [
            "model": APIKeyManager.deepSeekModel,
            "messages": [
                ["role": "system", "content": system],
                ["role": "user", "content": userContent]
            ],
            "response_format": ["type": "json_object"],
            "temperature": 0.1
        ]

        var request = URLRequest(url: APIKeyManager.deepSeekEndpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 90

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw AIServiceError.parsingError("AI 整理失败")
        }

        struct APIResponse: Decodable {
            struct Choice: Decodable {
                struct Message: Decodable { let content: String }
                let message: Message
            }
            let choices: [Choice]
        }

        let apiResponse = try JSONDecoder().decode(APIResponse.self, from: data)
        guard let content = apiResponse.choices.first?.message.content else {
            return StructuredExtraction(metrics: [], findings: [], recommendations: [], examDate: nil)
        }

        return parseStructuredJSON(content)
    }

    /// 兼容旧接口
    static func extractMetrics(from ocrText: String) async throws -> [ReportImporter.DraftMetric] {
        let sections = TextSections(summary: "", labTables: "", imaging: "", fullText: ocrText)
        let result = try await extractStructuredReport(from: sections)
        return result.metrics
    }

    static func parseStructuredJSON(_ content: String, source: ParseSource = .ocr) -> StructuredExtraction {
        let jsonString = extractJSONObject(from: content)
        guard let data = jsonString.data(using: .utf8) else {
            return StructuredExtraction(metrics: [], findings: [], recommendations: [], examDate: nil)
        }

        if let envelope = try? JSONDecoder().decode(ResponseEnvelope.self, from: data) {
            return mergeExtraction(from: envelope, source: source)
        }

        if let array = try? JSONDecoder().decode([MetricJSON].self, from: data) {
            let rawMetrics = array.flatMap { flattenToDrafts($0, source: source) }
            let metrics = source == .deepSeekPaste
                ? dedupeMetrics(rawMetrics.map { ReportMetricNormalizer.polish($0) })
                : ReportMetricNormalizer.filterMetrics(rawMetrics)
            return StructuredExtraction(metrics: metrics, findings: [], recommendations: [], examDate: nil)
        }

        return StructuredExtraction(metrics: [], findings: [], recommendations: [], examDate: nil)
    }

    private static func dedupeMetrics(_ metrics: [ReportImporter.DraftMetric]) -> [ReportImporter.DraftMetric] {
        let hasVisitDates = metrics.contains { $0.visitDate != nil }
        var seen = Set<String>()
        var result: [ReportImporter.DraftMetric] = []
        for item in metrics {
            let dateKey = item.visitDate.map { ReportDisplayFormatter.examDateLabel($0) } ?? ""
            let key = hasVisitDates
                ? "\(dateKey)|\(ReportMetricNormalizer.normalizeName(item.name).lowercased())"
                : ReportMetricNormalizer.normalizeName(item.name).lowercased()
            guard !key.isEmpty, !seen.contains(key) else { continue }
            seen.insert(key)
            result.append(item)
        }
        return result
    }

    static func mergeExtraction(
        from envelope: ResponseEnvelope,
        source: ParseSource,
        postProcess: Bool = true
    ) -> StructuredExtraction {
        let rawMetrics = (envelope.metrics ?? []).flatMap { flattenToDrafts($0, source: source) }
        let polished = rawMetrics.map { ReportMetricNormalizer.polish($0) }
        let metrics = source == .deepSeekPaste
            ? dedupeMetrics(polished)
            : ReportMetricNormalizer.filterMetrics(rawMetrics)
        let rawFindings = ReportMetricNormalizer.dedupeFindings(
            (envelope.findings ?? []).compactMap { toFinding($0) }
        )
        let recs = envelope.recommendations ?? []
        let visitDates = metrics.compactMap(\.visitDate) + rawFindings.compactMap(\.visitDate)
        let exam = parseExamDateString(envelope.examDate)
            ?? visitDates.max()
        let summary = envelope.assessmentNote?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        if !postProcess {
            return StructuredExtraction(
                metrics: metrics,
                findings: rawFindings,
                recommendations: recs,
                examDate: exam,
                assessmentSummary: summary
            )
        }

        let enrichedFindings = ImagingFollowUpEnricher.enrichAll(rawFindings)
        let promoted = ReportMetricExpander.promoteLabFindings(findings: enrichedFindings, metrics: metrics)
        let expandedMetrics = source == .deepSeekPaste
            ? dedupeMetrics(ReportMetricExpander.expand(promoted.metrics).map { ReportMetricNormalizer.polish($0) })
            : ReportMetricNormalizer.filterMetrics(ReportMetricExpander.expand(promoted.metrics))
        return StructuredExtraction(
            metrics: expandedMetrics,
            findings: promoted.findings,
            recommendations: recs,
            examDate: exam,
            assessmentSummary: summary
        )
    }

    /// 分段导入：解析阶段跳过重处理，校对前再调用
    static func finalizeExtraction(
        _ extraction: StructuredExtraction,
        source: ParseSource = .deepSeekPaste
    ) -> StructuredExtraction {
        let enrichedFindings = ImagingFollowUpEnricher.enrichAll(extraction.findings)
        let promoted = ReportMetricExpander.promoteLabFindings(
            findings: enrichedFindings,
            metrics: extraction.metrics
        )
        let expandedMetrics = source == .deepSeekPaste
            ? dedupeMetrics(ReportMetricExpander.expand(promoted.metrics).map { ReportMetricNormalizer.polish($0) })
            : ReportMetricNormalizer.filterMetrics(ReportMetricExpander.expand(promoted.metrics))
        return StructuredExtraction(
            metrics: expandedMetrics,
            findings: promoted.findings,
            recommendations: extraction.recommendations,
            examDate: extraction.examDate,
            assessmentSummary: extraction.assessmentSummary
        )
    }

    static func parseExamDateString(_ raw: String?) -> Date? {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return nil
        }
        let formats = ["yyyy-MM-dd", "yyyy/MM/dd", "yyyy.MM.dd", "yyyy年MM月dd日"]
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        for format in formats {
            formatter.dateFormat = format
            if let date = formatter.date(from: raw) { return date }
        }
        return nil
    }

    static func parseMetricsJSON(_ content: String) -> [ReportImporter.DraftMetric] {
        parseStructuredJSON(content).metrics
    }

    static func parseMetricItem(_ item: MetricJSON, source: ParseSource) -> ReportImporter.DraftMetric? {
        flattenToDrafts(item, source: source).first
    }

    /// 将 DeepSeek 输出的扁平原子行或 panel+items[] 转为 DraftMetric 列表
    static func flattenToDrafts(_ item: MetricJSON, source: ParseSource) -> [ReportImporter.DraftMetric] {
        if item.hasStructuredItems, let children = item.items {
            let panel = item.resolvedPanel.isEmpty ? item.resolvedName : item.resolvedPanel
            return children.compactMap { child in
                toDraft(child, source: source, inheritedPanel: panel, parent: item)
            }
        }
        guard let draft = toDraft(item, source: source) else { return [] }
        return [draft]
    }

    static func parseFindingItem(_ item: FindingJSON) -> ReportImporter.DraftFinding? {
        toFinding(item)
    }

    private static func toDraft(
        _ item: MetricJSON,
        source: ParseSource,
        inheritedPanel: String = "",
        parent: MetricJSON? = nil
    ) -> ReportImporter.DraftMetric? {
        let name = ReportMetricNormalizer.normalizeName(item.resolvedName)
        guard name.count >= 2 else { return nil }
        if source == .ocr, !ReportMetricNormalizer.isLikelyLabMetricName(name) { return nil }

        let valueText = item.resolvedValueText
        let value = item.value ?? Double(valueText.filter { $0.isNumber || $0 == "." })
        guard !valueText.isEmpty || value != nil else { return nil }

        if source == .ocr, ReportMetricNormalizer.isTimestampLike(valueText) { return nil }

        let sectionRaw = item.section ?? parent?.section
        let section = ReportMetricCategory.normalizeIncomingSection(sectionRaw, metricName: name)

        let panelCandidate = item.resolvedPanel.isEmpty ? inheritedPanel : item.resolvedPanel
        let panelName = panelCandidate.isEmpty
            ? ""
            : ReportMetricCategory.professionalPanelName(panelCandidate)

        let visitDate = parseExamDateString(item.visitDate) ?? parent.flatMap { parseExamDateString($0.visitDate) }

        var isAbnormal = item.isAbnormal ?? false
        if item.isAbnormal == nil, source == .deepSeekPaste {
            isAbnormal = ReportMetricNormalizer.inferAbnormal(
                value: value ?? 0,
                referenceRange: item.referenceRange ?? "",
                lineHint: name + valueText
            )
        }

        return ReportImporter.DraftMetric(
            name: name,
            valueText: valueText,
            value: value ?? 0,
            unit: ReportMetricNormalizer.normalizeUnit(item.unit ?? ""),
            referenceRange: item.referenceRange ?? "",
            isAbnormal: isAbnormal,
            section: section,
            visitDate: visitDate,
            severityRank: min(5, max(0, item.severityRank ?? parent?.severityRank ?? 0)),
            assessmentNote: item.assessmentNote?.trimmingCharacters(in: .whitespacesAndNewlines)
                ?? parent?.assessmentNote?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            panelName: panelName
        )
    }

    private static func toFinding(_ item: FindingJSON) -> ReportImporter.DraftFinding? {
        let title = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard title.count >= 2 else { return nil }
        let detail = item.detail?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let conclusion = item.conclusion?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        var assessment = item.assessmentNote?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if assessment.isEmpty, !conclusion.isEmpty {
            assessment = "结论：\(conclusion)"
        }
        let finding = ReportImporter.DraftFinding(
            category: item.category ?? "其他",
            title: title,
            detail: detail,
            isAbnormal: item.isAbnormal ?? true,
            visitDate: parseExamDateString(item.visitDate),
            severityRank: min(5, max(0, item.severityRank ?? 0)),
            assessmentNote: assessment,
            conclusion: conclusion,
            morphology: item.morphology?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            organSite: item.organSite?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            morphologyTags: item.morphologyTags ?? [],
            primarySizeMm: item.primarySizeMm,
            secondarySizeMm: item.secondarySizeMm,
            ctValueHu: item.ctValueHu
        )
        return ReportMetricNormalizer.enrichClinicalFinding(finding)
    }

    /// 脱敏：去除姓名、手机号、身份证号等再发送 DeepSeek
    static func sanitizeForCloud(_ text: String) -> String {
        var result = text
        result = result.replacingOccurrences(
            of: #"1[3-9]\d{9}"#,
            with: "[手机号已隐藏]",
            options: .regularExpression
        )
        result = result.replacingOccurrences(
            of: #"\d{17}[\dXx]"#,
            with: "[身份证已隐藏]",
            options: .regularExpression
        )
        result = result.replacingOccurrences(
            of: #"姓名[:：]?\s*[\u4e00-\u9fa5]{2,4}"#,
            with: "姓名:[已隐藏]",
            options: .regularExpression
        )
        result = result.replacingOccurrences(
            of: #"体检号[^\\n]{0,30}\d{8,}"#,
            with: "体检号:[已隐藏]",
            options: .regularExpression
        )
        return result
    }

    // MARK: - 严重度与分类 enrichment

    private struct RankItemJSON: Decodable {
        let index: Int
        let severityRank: Int?
        let section: String?
        let category: String?
        let assessmentNote: String?
    }

    private struct RankEnvelope: Decodable {
        let items: [RankItemJSON]?
    }

    /// 用 DeepSeek 为异常项标注严重度（1–5）与报告章节，失败时保留本地规则结果
    static func enrichDraftRanking(_ draft: ReportImporter.ImportDraft) async -> ReportImporter.ImportDraft {
        var copy = applyLocalSeverityRanking(draft)
        let itemCount = copy.metrics.count + copy.findings.count
        if itemCount > 80 || draft.rawText.utf8.count > 48_000 {
            return copy
        }
        guard APIKeyManager.isDeepSeekConfigured, APIKeyManager.isReportAIAssistEnabled,
              let apiKey = APIKeyManager.deepSeekAPIKey else {
            return copy
        }

        let payload = buildRankingPayload(from: copy)
        guard !payload.isEmpty else { return copy }

        let system = ReportDeepSeekPastePrompt.rankingSystemPrompt

        let body: [String: Any] = [
            "model": APIKeyManager.deepSeekModel,
            "messages": [
                ["role": "system", "content": system],
                ["role": "user", "content": payload]
            ],
            "response_format": ["type": "json_object"],
            "temperature": 0.1
        ]

        do {
            var request = URLRequest(url: APIKeyManager.deepSeekEndpoint)
            request.httpMethod = "POST"
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            request.timeoutInterval = 60

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                return copy
            }

            struct APIResponse: Decodable {
                struct Choice: Decodable {
                    struct Message: Decodable { let content: String }
                    let message: Message
                }
                let choices: [Choice]
            }

            let apiResponse = try JSONDecoder().decode(APIResponse.self, from: data)
            guard let content = apiResponse.choices.first?.message.content,
                  let jsonData = extractJSONObject(from: content).data(using: .utf8),
                  let envelope = try? JSONDecoder().decode(RankEnvelope.self, from: jsonData),
                  let items = envelope.items else {
                return copy
            }

            applyRankingItems(items, to: &copy)
        } catch {
            return copy
        }
        return copy
    }

    static func applyLocalSeverityRanking(_ draft: ReportImporter.ImportDraft) -> ReportImporter.ImportDraft {
        var copy = draft
        copy.metrics = copy.metrics.map { item in
            var metric = item
            if metric.severityRank == 0 {
                metric.severityRank = AbnormalitySeverityRanker.localRank(
                    name: metric.name,
                    detail: metric.valueText,
                    isAbnormal: metric.isAbnormal
                )
            }
            if metric.assessmentNote.isEmpty {
                metric.assessmentNote = AbnormalitySeverityRanker.localAssessmentNote(
                    name: metric.name,
                    detail: metric.valueText,
                    isAbnormal: metric.isAbnormal,
                    severityRank: metric.severityRank
                )
            }
            if metric.section.isEmpty {
                ReportMetricCategory.assignSection(to: &metric)
            }
            return metric
        }
        copy.findings = copy.findings.map { item in
            var finding = item
            if finding.severityRank == 0 {
                finding.severityRank = AbnormalitySeverityRanker.localRank(
                    name: finding.title,
                    detail: finding.detail,
                    isAbnormal: finding.isAbnormal
                )
            }
            if finding.assessmentNote.isEmpty, finding.conclusion.isEmpty {
                finding.assessmentNote = AbnormalitySeverityRanker.localAssessmentNote(
                    name: finding.title,
                    detail: finding.detail,
                    isAbnormal: finding.isAbnormal,
                    severityRank: finding.severityRank
                )
            }
            return finding
        }
        return copy
    }

    private static func buildRankingPayload(from draft: ReportImporter.ImportDraft) -> String {
        var lines: [String] = []
        var index = 0
        for metric in draft.metrics {
            let flag = metric.isAbnormal ? "异常" : "正常"
            lines.append("[\(index)] 指标 \(flag)：\(metric.name) \(metric.valueText)")
            index += 1
        }
        for finding in draft.findings {
            let flag = finding.isAbnormal ? "异常" : "正常"
            let detail = finding.detail.isEmpty ? finding.title : "\(finding.title) \(finding.detail)"
            lines.append("[\(index)] 结论 \(flag)：\(detail)")
            index += 1
        }
        guard !lines.isEmpty else { return "" }
        return "请为以下条目标注 severityRank、section、category：\n" + lines.joined(separator: "\n")
    }

    private static func applyRankingItems(_ items: [RankItemJSON], to draft: inout ReportImporter.ImportDraft) {
        let metricCount = draft.metrics.count
        for item in items {
            let rank = min(5, max(0, item.severityRank ?? 0))
            guard item.index >= 0 else { continue }
            if item.index < metricCount {
                if rank > 0 { draft.metrics[item.index].severityRank = rank }
                if let section = item.section?.trimmingCharacters(in: .whitespacesAndNewlines), !section.isEmpty {
                    draft.metrics[item.index].section = section
                }
                if let note = item.assessmentNote?.trimmingCharacters(in: .whitespacesAndNewlines), !note.isEmpty {
                    draft.metrics[item.index].assessmentNote = note
                }
            } else {
                let findingIndex = item.index - metricCount
                guard findingIndex < draft.findings.count else { continue }
                if rank > 0 { draft.findings[findingIndex].severityRank = rank }
                if let category = item.category?.trimmingCharacters(in: .whitespacesAndNewlines), !category.isEmpty {
                    draft.findings[findingIndex].category = category
                }
                if let note = item.assessmentNote?.trimmingCharacters(in: .whitespacesAndNewlines), !note.isEmpty {
                    draft.findings[findingIndex].assessmentNote = note
                }
            }
        }
    }

    private static func extractJSONObject(from text: String) -> String {
        if let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}") {
            return String(text[start...end])
        }
        if let start = text.firstIndex(of: "["), let end = text.lastIndex(of: "]") {
            return String(text[start...end])
        }
        return text
    }
}

/// 本地异常严重度估计（DeepSeek 不可用时的兜底）
/// @author jiali.qiu
enum AbnormalitySeverityRanker {

    static func localRank(name: String, detail: String, isAbnormal: Bool) -> Int {
        guard isAbnormal else { return 0 }
        let blob = RiskAnalyzer.normalize(name + detail)
        if blob.contains("恶性") || blob.contains("转移") || blob.contains("危急") { return 5 }
        if blob.contains("磨玻璃") || blob.contains("占位") || blob.contains("低回声结节") { return 4 }
        if blob.contains("结节") || blob.contains("血管瘤") || blob.contains("fnh") { return 3 }
        if blob.contains("增生") || blob.contains("升高") || blob.contains("偏高") || blob.contains("超标") { return 2 }
        return 1
    }

    static func localAssessmentNote(
        name: String,
        detail: String,
        isAbnormal: Bool,
        severityRank: Int
    ) -> String {
        guard isAbnormal else {
            return "未见明显异常，待同项复查对比"
        }
        let blob = RiskAnalyzer.normalize(name + detail)
        switch severityRank {
        case 5:
            return "需优先关注，建议尽快遵医嘱复查或专科就诊"
        case 4:
            if blob.contains("磨玻璃") || blob.contains("结节") {
                return "影像异常需短间隔复查，关注尺寸与性质变化"
            }
            return "指标或结论明显偏离，建议按医嘱复查"
        case 3:
            if blob.contains("血管瘤") || blob.contains("fnh") {
                return "良性可能大，建议定期影像随访对比尺寸"
            }
            if blob.contains("结节") {
                return "结节需定期复查，关注是否增大或性质改变"
            }
            return "建议 3–12 个月内同项复查对比"
        case 2:
            return "轻度异常，建议生活方式调整并复查"
        default:
            return "轻微偏离，可常规随访"
        }
    }
}
