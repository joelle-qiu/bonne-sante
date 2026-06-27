import Foundation

/// DeepSeek 网页粘贴内容的容错 JSON 解析（修复常见格式问题 + 片段提取）
/// @author zhi.qu
enum ReportPasteParser {

    /// 多策略解析粘贴文本
    static func parse(_ raw: String, source: ReportAIService.ParseSource = .deepSeekPaste) -> ReportAIService.StructuredExtraction {
        let cleaned = sanitize(raw)

        // 0. CT/MRI 随访 findings 片段（小体积粘贴）
        if ImagingFollowUpEnricher.isImagingFollowUpPaste(cleaned),
           let imaging = parseImagingFollowUpFragment(cleaned) {
            return imaging
        }

        // 0b. 多份 JSON 连续粘贴（含 markdown 代码块、单行间隔的多报告 — fixture 需扫全文件）
        if let merged = parseMultipleJSONObjects(from: cleaned, source: source), !merged.isEmpty {
            return merged
        }

        // 0a. 纯空行分隔、无 markdown 包裹时的快路径
        if !cleaned.contains("```"),
           let blankLineMerged = parseBlankLineSeparatedObjects(from: cleaned, source: source),
           !blankLineMerged.isEmpty {
            return blankLineMerged
        }

        // 1. 标准 JSON（平衡括号提取）
        if let json = extractBalancedJSONObject(from: cleaned),
           let result = decodeEnvelope(json, source: source),
           !result.isEmpty {
            return result
        }

        // 2. 修复 trailing comma、再试
        if let json = extractBalancedJSONObject(from: cleaned).map(repairJSON),
           let result = decodeEnvelope(json, source: source),
           !result.isEmpty {
            return result
        }

        // 3. 裸数组：[{...}] → 视为 findings 或 metrics
        if let arrayJSON = extractBalancedJSONArray(from: cleaned) {
            if let findings = decodeFindingsArray(arrayJSON), !findings.isEmpty {
                return ReportAIService.StructuredExtraction(
                    metrics: [], findings: findings, recommendations: extractRecommendations(from: cleaned), examDate: nil
                )
            }
            if let metrics = decodeMetricsArray(arrayJSON, source: source), !metrics.isEmpty {
                return ReportAIService.StructuredExtraction(
                    metrics: metrics, findings: [], recommendations: extractRecommendations(from: cleaned), examDate: nil
                )
            }
        }

        // 4. 正则片段提取（JSON 语法损坏时；大文件跳过避免 CPU 卡死）
        if cleaned.utf8.count > 16_384 {
            return ReportAIService.StructuredExtraction(
                metrics: [], findings: [], recommendations: [], examDate: nil
            )
        }

        let metrics = extractMetricsByPattern(from: cleaned, source: source)
        let findings = extractFindingsByPattern(from: cleaned)
        let recs = extractRecommendations(from: cleaned)
        let exam = extractExamDate(from: cleaned)

        return ReportAIService.StructuredExtraction(
            metrics: metrics,
            findings: findings,
            recommendations: recs,
            examDate: exam
        )
    }

    /// 按顶层 `{...}` 拆成多段，不合并（分段校对入库）
    static func parseSegments(
        _ raw: String,
        source: ReportAIService.ParseSource = .deepSeekPaste
    ) -> [ReportAIService.StructuredExtraction] {
        let cleaned = sanitize(raw)

        if ImagingFollowUpEnricher.isImagingFollowUpPaste(cleaned),
           let imaging = parseImagingFollowUpFragment(cleaned) {
            return [imaging]
        }

        // 空行分块快路径（fixture：多段单行 JSON + markdown 块）
        if let chunked = parseSegmentsFromBlankLineChunks(from: cleaned, source: source) {
            return chunked
        }

        let segments = decodeTopLevelEnvelopeSegments(from: cleaned, source: source, postProcess: false)
        if segments.count >= 2 {
            return segments
        }
        if segments.count == 1 {
            return segments
        }

        let full = parse(cleaned, source: source)
        if !full.isEmpty {
            return [full]
        }
        return []
    }

    /// 空行分隔的多份 JSON（跳过顶层扫描，直接按块解码）
    private static func parseSegmentsFromBlankLineChunks(
        from text: String,
        source: ReportAIService.ParseSource
    ) -> [ReportAIService.StructuredExtraction]? {
        guard text.contains("\n\n") else { return nil }

        var segments: [ReportAIService.StructuredExtraction] = []
        for part in text.components(separatedBy: "\n\n") {
            var chunk = stripMarkdownFence(part.trimmingCharacters(in: .whitespacesAndNewlines))
            chunk = stripLeadingNonJSON(chunk)
            guard !chunk.isEmpty else { continue }

            let objectJSON: String?
            if chunk.hasSuffix("}") && !chunk.contains("\n") {
                objectJSON = chunk
            } else {
                objectJSON = extractBalancedJSONObject(from: chunk)
            }
            guard let objectJSON else { continue }
            guard let candidate = decodeEnvelopeLight(objectJSON, source: source)
                ?? decodeEnvelopeLight(repairJSON(objectJSON), source: source),
                  !candidate.isEmpty else { continue }
            segments.append(candidate)
        }
        guard segments.count >= 2 else { return nil }
        return segments
    }

    /// 单次扫描提取顶层 `{...}` 并解码（O(n)，避免对每个 `{` 重复平衡扫描）
    private static func decodeTopLevelEnvelopeSegments(
        from text: String,
        source: ReportAIService.ParseSource,
        postProcess: Bool = true
    ) -> [ReportAIService.StructuredExtraction] {
        let objectJSONs = extractTopLevelJSONObjects(from: text)
        var segments: [ReportAIService.StructuredExtraction] = []
        for objectJSON in objectJSONs.prefix(32) {
            let candidate: ReportAIService.StructuredExtraction?
            if postProcess {
                candidate = decodeEnvelope(objectJSON, source: source)
                    ?? decodeEnvelope(repairJSON(objectJSON), source: source)
            } else {
                candidate = decodeEnvelopeLight(objectJSON, source: source)
                    ?? decodeEnvelopeLight(repairJSON(objectJSON), source: source)
            }
            guard let candidate, !candidate.isEmpty else { continue }
            segments.append(candidate)
        }
        return segments
    }

    private static func stripLeadingNonJSON(_ text: String) -> String {
        guard let brace = text.firstIndex(of: "{") else { return text }
        return String(text[brace...]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 分段展示用日期/摘要标签
    static func segmentLabel(from extraction: ReportAIService.StructuredExtraction) -> String {
        let visitDates = extraction.metrics.compactMap(\.visitDate)
            + extraction.findings.compactMap(\.visitDate)
        if let exam = extraction.examDate ?? visitDates.max() {
            return ReportDisplayFormatter.examDateLabel(exam)
        }
        let metricCount = extraction.metrics.count
        let findingCount = extraction.findings.count
        if metricCount + findingCount > 0 {
            return "\(metricCount) 项指标 · \(findingCount) 项结论"
        }
        return "未标注日期"
    }

    /// 按空行切分多份顶层 JSON（常见导出格式）
    private static func parseBlankLineSeparatedObjects(
        from text: String,
        source: ReportAIService.ParseSource
    ) -> ReportAIService.StructuredExtraction? {
        let chunks = text.components(separatedBy: "\n\n")
            .map { stripMarkdownFence($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
            .filter { $0.hasPrefix("{") && $0.hasSuffix("}") }
        guard chunks.count >= 2 else { return nil }

        var merged = ReportAIService.StructuredExtraction(
            metrics: [], findings: [], recommendations: [], examDate: nil, assessmentSummary: ""
        )
        var parsedAny = false
        for chunk in chunks {
            guard let candidate = decodeEnvelope(chunk, source: source)
                ?? decodeEnvelope(repairJSON(chunk), source: source),
                  !candidate.isEmpty else { continue }
            merged = mergeExtractions(merged, candidate)
            parsedAny = true
        }
        return parsedAny ? merged : nil
    }

    private static func stripMarkdownFence(_ block: String) -> String {
        var lines = block.components(separatedBy: .newlines)
        if lines.first?.lowercased().hasPrefix("```") == true {
            lines.removeFirst()
        }
        if lines.last?.trimmingCharacters(in: .whitespaces) == "```" {
            lines.removeLast()
        }
        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func sanitize(_ text: String) -> String {
        var s = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // 去掉 markdown 代码块
        s = s.replacingOccurrences(of: "```json", with: "", options: .caseInsensitive)
        s = s.replacingOccurrences(of: "```", with: "")
        // 智能引号 → 直引号
        s = s.replacingOccurrences(of: "\u{201C}", with: "\"")
            .replacingOccurrences(of: "\u{201D}", with: "\"")
            .replacingOccurrences(of: "\u{2018}", with: "'")
            .replacingOccurrences(of: "\u{2019}", with: "'")
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func repairJSON(_ json: String) -> String {
        var s = json
        // 去掉 trailing comma：,]  ,}
        s = s.replacingOccurrences(of: #",\s*]"#, with: "]", options: .regularExpression)
        s = s.replacingOccurrences(of: #",\s*}"#, with: "}", options: .regularExpression)
        return s
    }

    // MARK: - Balanced extract

    private static func extractBalancedJSONObject(from text: String) -> String? {
        guard let start = text.firstIndex(of: "{") else { return nil }
        return extractBalanced(from: text, start: start, open: "{", close: "}")
    }

    /// 逐段提取顶层 `{...}` 并合并
    private static func parseMultipleJSONObjects(
        from text: String,
        source: ReportAIService.ParseSource
    ) -> ReportAIService.StructuredExtraction? {
        let segments = decodeTopLevelEnvelopeSegments(from: text, source: source)
        guard !segments.isEmpty else { return nil }

        var merged = segments[0]
        for segment in segments.dropFirst() {
            merged = mergeExtractions(merged, segment)
        }
        return merged
    }

    /// 大粘贴内容入库用摘要（避免 SwiftData / 校对页持有完整 JSON）
    static func compactStorageText(for text: String, maxChars: Int = 2048) -> String {
        guard text.utf8.count > maxChars else { return text }
        let kb = max(1, text.utf8.count / 1024)
        let head = String(text.prefix(maxChars))
        return head + "\n\n…（原文约 \(kb) KB，已完整解析；此处仅保留摘要预览）"
    }

    private static func mergeExtractions(
        _ left: ReportAIService.StructuredExtraction,
        _ right: ReportAIService.StructuredExtraction
    ) -> ReportAIService.StructuredExtraction {
        var recs = left.recommendations
        for item in right.recommendations where !recs.contains(item) {
            recs.append(item)
        }
        let visitDates = left.metrics.compactMap(\.visitDate)
            + right.metrics.compactMap(\.visitDate)
            + left.findings.compactMap(\.visitDate)
            + right.findings.compactMap(\.visitDate)
        let exam = left.examDate ?? right.examDate ?? visitDates.max()
        var summary = left.assessmentSummary
        if !right.assessmentSummary.isEmpty, !summary.contains(right.assessmentSummary) {
            summary = summary.isEmpty ? right.assessmentSummary : "\(summary)；\(right.assessmentSummary)"
        }
        return ReportAIService.StructuredExtraction(
            metrics: left.metrics + right.metrics,
            findings: left.findings + right.findings,
            recommendations: recs,
            examDate: exam,
            assessmentSummary: summary
        )
    }

    private static func extractBalancedJSONArray(from text: String) -> String? {
        guard let start = text.firstIndex(of: "[") else { return nil }
        return extractBalanced(from: text, start: start, open: "[", close: "]")
    }

    /// 单次遍历提取所有顶层 `{...}`（不计入字符串内的括号）
    private static func extractTopLevelJSONObjects(from text: String) -> [String] {
        var results: [String] = []
        var depth = 0
        var inString = false
        var escaped = false
        var objectStart: String.Index?

        for index in text.indices {
            let char = text[index]
            if inString {
                if escaped { escaped = false }
                else if char == "\\" { escaped = true }
                else if char == "\"" { inString = false }
                continue
            }
            if char == "\"" {
                inString = true
                continue
            }
            if char == "{" {
                if depth == 0 {
                    objectStart = index
                }
                depth += 1
            } else if char == "}" {
                depth -= 1
                if depth == 0, let start = objectStart {
                    results.append(String(text[start...index]))
                    objectStart = nil
                }
            }
        }
        return results
    }

    private static func extractBalanced(from text: String, start: String.Index, open: Character, close: Character) -> String? {
        var depth = 0
        var inString = false
        var escaped = false

        for index in text.indices[start...] {
            let char = text[index]
            if inString {
                if escaped { escaped = false }
                else if char == "\\" { escaped = true }
                else if char == "\"" { inString = false }
                continue
            }
            if char == "\"" { inString = true; continue }
            if char == open { depth += 1 }
            if char == close {
                depth -= 1
                if depth == 0 {
                    return String(text[start...index])
                }
            }
        }
        return nil
    }

    // MARK: - Decode

    private struct Envelope: Decodable {
        let examDate: String?
        let metrics: [ReportAIService.MetricJSON]?
        let findings: [ReportAIService.FindingJSON]?
        let recommendations: [String]?
        let assessmentNote: String?
    }

    private static func decodeEnvelope(_ json: String, source: ReportAIService.ParseSource) -> ReportAIService.StructuredExtraction? {
        decodeEnvelope(json, source: source, postProcess: true)
    }

    /// 分段扫描用：仅 JSON 解码 + 扁平化，不做 expand/enrich（避免导入阶段 CPU 峰值）
    private static func decodeEnvelopeLight(
        _ json: String,
        source: ReportAIService.ParseSource
    ) -> ReportAIService.StructuredExtraction? {
        decodeEnvelope(json, source: source, postProcess: false)
    }

    private static func decodeEnvelope(
        _ json: String,
        source: ReportAIService.ParseSource,
        postProcess: Bool
    ) -> ReportAIService.StructuredExtraction? {
        guard let data = json.data(using: .utf8),
              let envelope = try? JSONDecoder().decode(Envelope.self, from: data) else {
            return nil
        }
        return buildExtraction(from: envelope, source: source, postProcess: postProcess)
    }

    private static func buildExtraction(
        from envelope: Envelope,
        source: ReportAIService.ParseSource,
        postProcess: Bool = true
    ) -> ReportAIService.StructuredExtraction {
        ReportAIService.mergeExtraction(
            from: ReportAIService.ResponseEnvelope(
                examDate: envelope.examDate,
                metrics: envelope.metrics,
                findings: envelope.findings,
                recommendations: envelope.recommendations,
                assessmentNote: envelope.assessmentNote
            ),
            source: source,
            postProcess: postProcess
        )
    }

    private static func decodeFindingsArray(_ json: String) -> [ReportImporter.DraftFinding]? {
        guard let data = json.data(using: .utf8),
              let items = try? JSONDecoder().decode([ReportAIService.FindingJSON].self, from: data) else {
            return nil
        }
        let findings = items.compactMap { ReportAIService.parseFindingItem($0) }
        return findings.isEmpty ? nil : findings
    }

    private static func decodeMetricsArray(_ json: String, source: ReportAIService.ParseSource) -> [ReportImporter.DraftMetric]? {
        guard let data = json.data(using: .utf8),
              let items = try? JSONDecoder().decode([ReportAIService.MetricJSON].self, from: data) else {
            return nil
        }
        let metrics = items.flatMap { ReportAIService.flattenToDrafts($0, source: source) }
        return metrics.isEmpty ? nil : dedupeMetrics(metrics.map { ReportMetricNormalizer.polish($0) })
    }

    private static func dedupeMetrics(_ metrics: [ReportImporter.DraftMetric]) -> [ReportImporter.DraftMetric] {
        var seen = Set<String>()
        return metrics.filter { item in
            let key = ReportMetricNormalizer.normalizeName(item.name).lowercased()
            guard !seen.contains(key) else { return false }
            seen.insert(key)
            return true
        }
    }

    // MARK: - Regex fallback

    private static func extractFindingsByPattern(from text: String) -> [ReportImporter.DraftFinding] {
        var results: [ReportImporter.DraftFinding] = []
        let pattern = #""category"\s*:\s*"([^"]*?)"\s*,\s*"title"\s*:\s*"([^"]*?)"(?:\s*,\s*"detail"\s*:\s*"([^"]*?)")?\s*,\s*"isAbnormal"\s*:\s*(true|false)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else {
            return fallbackFindingTitles(from: text)
        }
        let range = NSRange(text.startIndex..., in: text)
        regex.enumerateMatches(in: text, range: range) { match, _, _ in
            guard let match else { return }
            func group(_ i: Int) -> String {
                guard let r = Range(match.range(at: i), in: text) else { return "" }
                return String(text[r])
            }
            let title = group(2)
            guard title.count >= 2 else { return }
            results.append(ReportImporter.DraftFinding(
                category: group(1).isEmpty ? "其他" : group(1),
                title: title,
                detail: group(3),
                isAbnormal: group(4) == "true"
            ))
        }
        if results.isEmpty { return fallbackFindingTitles(from: text) }
        return results
    }

    private static func fallbackFindingTitles(from text: String) -> [ReportImporter.DraftFinding] {
        var results: [ReportImporter.DraftFinding] = []
        let titlePattern = #""title"\s*:\s*"([^"]{2,40})""#
        guard let regex = try? NSRegularExpression(pattern: titlePattern) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        regex.enumerateMatches(in: text, range: range) { match, _, _ in
            guard let match, let r = Range(match.range(at: 1), in: text) else { return }
            let title = String(text[r])
            if !results.contains(where: { $0.title == title }) {
                results.append(ReportImporter.DraftFinding(category: "其他", title: title, detail: "", isAbnormal: true))
            }
        }
        return results
    }

    private static func extractMetricsByPattern(from text: String, source: ReportAIService.ParseSource) -> [ReportImporter.DraftMetric] {
        var results: [ReportImporter.DraftMetric] = []
        let pattern = #""name"\s*:\s*"([^"]+?)".*?"value(?:Text)?"\s*:\s*("([^"]*?)"|([\d.]+))"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else {
            return []
        }
        let range = NSRange(text.startIndex..., in: text)
        regex.enumerateMatches(in: text, range: range) { match, _, _ in
            guard let match else { return }
            func group(_ i: Int) -> String {
                guard match.range(at: i).location != NSNotFound,
                      let r = Range(match.range(at: i), in: text) else { return "" }
                return String(text[r])
            }
            let name = group(1)
            let valueText = group(3).isEmpty ? group(4) : group(3)
            guard name.count >= 2, !valueText.isEmpty else { return }
            let value = Double(valueText.filter { $0.isNumber || $0 == "." }) ?? 0
            results.append(ReportImporter.DraftMetric(
                name: ReportMetricNormalizer.normalizeName(name),
                valueText: valueText,
                value: value,
                unit: "",
                referenceRange: "",
                isAbnormal: false
            ))
        }
        return dedupeMetrics(results.map { ReportMetricNormalizer.polish($0) })
    }

    /// 解析肺结节 / 肝血管瘤等影像随访粘贴片段
    private static func parseImagingFollowUpFragment(_ text: String) -> ReportAIService.StructuredExtraction? {
        guard let arrayJSON = extractBalancedJSONArray(from: text),
              var findings = decodeFindingsArray(arrayJSON),
              !findings.isEmpty else {
            return nil
        }
        findings = ImagingFollowUpEnricher.enrichAll(findings)
        let recs = extractRecommendations(from: text)
        let visitDates = findings.compactMap(\.visitDate)
        return ReportAIService.StructuredExtraction(
            metrics: [],
            findings: findings,
            recommendations: recs,
            examDate: visitDates.max(),
            assessmentSummary: ImagingFollowUpEnricher.buildAssessmentSummary(from: findings)
        )
    }

    private static func extractRecommendations(from text: String) -> [String] {
        // "recommendations": ["...", "..."]
        guard let range = text.range(of: #""recommendations"\s*:\s*\["#, options: .regularExpression) else {
            return []
        }
        let tail = String(text[range.upperBound...])
        guard let end = tail.firstIndex(of: "]") else { return [] }
        let inner = String(tail[..<end])
        var recs: [String] = []
        let itemPattern = #""((?:\\.|[^"\\])*)""#
        guard let regex = try? NSRegularExpression(pattern: itemPattern) else { return [] }
        let nsRange = NSRange(inner.startIndex..., in: inner)
        regex.enumerateMatches(in: inner, range: nsRange) { match, _, _ in
            guard let match, let r = Range(match.range(at: 1), in: inner) else { return }
            let s = String(inner[r]).trimmingCharacters(in: .whitespaces)
            if s.count >= 4 { recs.append(s) }
        }
        return recs
    }

    private static func extractExamDate(from text: String) -> Date? {
        guard let regex = try? NSRegularExpression(pattern: #""examDate"\s*:\s*"(\d{4}-\d{2}-\d{2})""#),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let r = Range(match.range(at: 1), in: text) else {
            return nil
        }
        return ReportAIService.parseExamDateString(String(text[r]))
    }
}

/// 多策略化验行解析：适应冒号、等号、制表符、空格分隔等不同输入
/// @author jiali.qiu
enum HealthMetricLineParser {

    private static let rejectNameFragments = [
        "检查部位", "检查描述", "检查所见", "诊断结论", "审核者", "检验报告", "项目名称"
    ]

    /// 从单行文本提取指标（多种格式）
    static func parse(_ line: String, panelSection: String = "") -> ReportImporter.DraftMetric? {
        let clean = stripMarkdown(line).trimmingCharacters(in: CharacterSet.whitespaces)
        guard clean.count >= 4 else { return nil }

        guard let draft = parseKeyValue(clean, separator: "：")
            ?? parseKeyValue(clean, separator: ":")
            ?? parseKeyValue(clean, separator: "=")
            ?? parseDelimited(clean)
            ?? parseSpaced(clean) else {
            return nil
        }
        guard var finalized = finalize(draft, lineHint: line, panelSection: panelSection) else {
            return nil
        }
        finalized = applyResolution(finalized)
        return finalized
    }

    // MARK: - Strategies

    private static func parseKeyValue(_ line: String, separator: Character) -> ReportImporter.DraftMetric? {
        guard line.contains(separator) else { return nil }
        guard let index = line.firstIndex(of: separator) else { return nil }

        let name = String(line[..<index]).trimmingCharacters(in: CharacterSet.whitespaces)
        let valuePart = String(line[line.index(after: index)...]).trimmingCharacters(in: CharacterSet.whitespaces)
        guard isValidName(name), !valuePart.isEmpty else { return nil }

        return buildMetric(name: name, valuePart: valuePart, lineHint: line)
    }

    private static func parseDelimited(_ line: String) -> ReportImporter.DraftMetric? {
        let parts: [String]
        if line.contains("\t") {
            parts = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
        } else if line.contains("|") {
            parts = line.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        } else {
            return nil
        }
        guard parts.count >= 2 else { return nil }
        let name = parts[0].trimmingCharacters(in: CharacterSet.whitespaces)
        let valuePart = parts[1...].joined(separator: " ").trimmingCharacters(in: CharacterSet.whitespaces)
        guard isValidName(name), !valuePart.isEmpty else { return nil }
        return buildMetric(name: name, valuePart: valuePart, lineHint: line)
    }

    private static func parseSpaced(_ line: String) -> ReportImporter.DraftMetric? {
        guard let regex = try? NSRegularExpression(
            pattern: #"^([A-Za-z\u4e00-\u9fa5（）().\-/]{2,40}?)\s+([\d.><][\d.\sA-Za-z/%×^\-+（）().μ]*.*)$"#
        ),
              let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
              let nameRange = Range(match.range(at: 1), in: line),
              let valueRange = Range(match.range(at: 2), in: line) else {
            return nil
        }

        let name = String(line[nameRange]).trimmingCharacters(in: CharacterSet.whitespaces)
        let valuePart = String(line[valueRange]).trimmingCharacters(in: CharacterSet.whitespaces)
        guard isValidName(name), valuePart.range(of: #"\d"#, options: .regularExpression) != nil else { return nil }
        return buildMetric(name: name, valuePart: valuePart, lineHint: line)
    }

    // MARK: - Build

    private static func buildMetric(name: String, valuePart: String, lineHint: String) -> ReportImporter.DraftMetric? {
        let normalizedName = ReportMetricNormalizer.normalizeName(name)
        guard ReportMetricNormalizer.isLikelyLabMetricName(normalizedName) else { return nil }

        var valuePart = valuePart
        let referenceRange = extractReference(from: &valuePart)

        valuePart = valuePart
            .replacingOccurrences(of: "（-）", with: "")
            .replacingOccurrences(of: "（+）", with: "")
            .replacingOccurrences(of: "(-)", with: "")
            .replacingOccurrences(of: "(+)", with: "")
            .trimmingCharacters(in: CharacterSet.whitespaces)

        valuePart = normalizeSuperscripts(valuePart)

        let abnormal = lineHint.contains("↑") || lineHint.contains("↓")
            || valuePart.contains("略低") || valuePart.contains("略高")
            || valuePart.contains("强阳性") || valuePart.contains("临界")
            || lineHint.contains("（+）") || lineHint.contains("(+)")

        var value: Double = 0
        if valuePart.hasPrefix(">") || valuePart.hasPrefix("<") {
            let numeric = valuePart.dropFirst().filter { $0.isNumber || $0 == "." }
            value = Double(numeric) ?? 0
        } else if valuePart.contains("低于检出") || valuePart.contains("阴性") {
            value = 0
        } else if let match = valuePart.range(of: #"[\d.]+"#, options: .regularExpression) {
            value = Double(valuePart[match]) ?? 0
        }

        let unit = ReportMetricNormalizer.extractAndFixUnit(from: valuePart, explicitUnit: "")

        return ReportImporter.DraftMetric(
            name: normalizedName,
            valueText: valuePart,
            value: value,
            unit: unit,
            referenceRange: referenceRange,
            isAbnormal: abnormal
        )
    }

    private static func finalize(
        _ metric: ReportImporter.DraftMetric,
        lineHint: String,
        panelSection: String
    ) -> ReportImporter.DraftMetric? {
        var copy = ReportMetricNormalizer.polish(metric, lineHint: lineHint)
        guard ReportMetricNormalizer.isValidMetric(copy) else { return nil }
        if !panelSection.isEmpty { copy.section = panelSection }
        ReportMetricCategory.assignSection(to: &copy)
        return copy
    }

    private static func applyResolution(_ metric: ReportImporter.DraftMetric) -> ReportImporter.DraftMetric {
        let resolution = MetricNameCanonicalizer.resolve(metric.name)
        guard resolution.confidence >= 0.42 else { return metric }
        var copy = metric
        copy.name = resolution.displayName
        return copy
    }

    // MARK: - Helpers

    private static func isValidName(_ name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: CharacterSet.whitespaces)
        guard (2...40).contains(trimmed.count) else { return false }
        if rejectNameFragments.contains(where: { trimmed.contains($0) }) { return false }
        if ReportMetricNormalizer.isPanelHeader(trimmed) { return false }
        return true
    }

    private static func extractReference(from valuePart: inout String) -> String {
        let patterns = [
            #"（参考[^）]*）"#,
            #"\(参考[^)]*\)"#,
            #"\[参考[^\]]*\]"#,
            #"参考[:：]?\s*[\d.<>-]+(?:\s*-\s*[\d.]+)?"#
        ]
        for pattern in patterns {
            if let range = valuePart.range(of: pattern, options: .regularExpression) {
                let raw = String(valuePart[range])
                valuePart.removeSubrange(range)
                valuePart = valuePart.trimmingCharacters(in: CharacterSet.whitespaces)
                return raw
                    .replacingOccurrences(of: "（参考", with: "")
                    .replacingOccurrences(of: "(参考", with: "")
                    .replacingOccurrences(of: "[参考", with: "")
                    .replacingOccurrences(of: "）", with: "")
                    .replacingOccurrences(of: ")", with: "")
                    .replacingOccurrences(of: "]", with: "")
                    .replacingOccurrences(of: "参考:", with: "")
                    .replacingOccurrences(of: "参考：", with: "")
                    .trimmingCharacters(in: CharacterSet.whitespaces)
            }
        }
        return ""
    }

    private static func normalizeSuperscripts(_ text: String) -> String {
        let map: [Character: Character] = [
            "⁰": "0", "¹": "1", "²": "2", "³": "3", "⁴": "4",
            "⁵": "5", "⁶": "6", "⁷": "7", "⁸": "8", "⁹": "9"
        ]
        var result = ""
        for char in text {
            result.append(map[char] ?? char)
        }
        return result
            .replacingOccurrences(of: "×10", with: "×10^")
            .replacingOccurrences(of: "x10", with: "×10^")
    }

    private static func stripMarkdown(_ text: String) -> String {
        var s = text.trimmingCharacters(in: CharacterSet.whitespaces)
        while s.hasPrefix("- ") || s.hasPrefix("* ") || s.hasPrefix("• ") || s.hasPrefix("· ") {
            s = String(s.dropFirst(2)).trimmingCharacters(in: CharacterSet.whitespaces)
        }
        return s
            .replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "__", with: "")
            .trimmingCharacters(in: CharacterSet.whitespaces)
    }
}

/// 门诊结论 / 零散化验单自由文本解析（非 JSON，支持 Markdown 病程记录）
/// @author jiali.qiu
enum ReportClinicNoteParser {

    private struct VisitBlock {
        let date: Date?
        let title: String
        let lines: [String]
    }

    private enum ParseMode {
        case general
        case inFindings
    }

    private static let fieldLabels = ["检查部位", "检查描述", "检查所见", "诊断结论"]
    private static let panelHeaders = [
        "凝血功能", "心脏标志物", "感染性标志物", "感染性标志物（病毒抗体）",
        "生化", "血常规", "甲状腺功能", "免疫组", "未知时间"
    ]

    /// 解析门诊文字：先尝试 JSON，再 Markdown 病程结构
    static func parse(_ raw: String) -> ReportAIService.StructuredExtraction {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return ReportAIService.StructuredExtraction(metrics: [], findings: [], recommendations: [], examDate: nil)
        }

        if trimmed.contains("{") || trimmed.contains("[") {
            let json = ReportPasteParser.parse(trimmed, source: .deepSeekPaste)
            if !json.isEmpty { return json }
        }

        let visits = splitVisits(trimmed)
        var allMetrics: [ReportImporter.DraftMetric] = []
        var allFindings: [ReportImporter.DraftFinding] = []
        var allRecommendations: [String] = []
        var visitDates: [Date] = []

        for visit in visits {
            let parsed = stampVisitDate(parseVisit(visit), date: visit.date)
            allMetrics.append(contentsOf: parsed.metrics)
            allFindings.append(contentsOf: parsed.findings)
            allRecommendations.append(contentsOf: parsed.recommendations)
            if let date = visit.date { visitDates.append(date) }
        }

        allMetrics = ReportMetricNormalizer.filterMetrics(
            dedupeMetrics(allMetrics.map { ReportMetricNormalizer.polish($0) }, visitCount: visits.count)
        )
        allFindings = ReportMetricNormalizer.dedupeFindings(allFindings.filter { finding in
            !ReportMetricNormalizer.isJunkClinicFinding(finding)
        })

        // 兜底：对未进入 visit 结构的行再做一轮智能扫描
        let rescanned = rescanUnstructuredLines(trimmed, existingMetrics: allMetrics)
        allMetrics = ReportMetricNormalizer.filterMetrics(allMetrics + rescanned)

        var recommendations = Array(allRecommendations.prefix(12))
        if visits.count > 1 {
            let labels = visitDates.sorted().map { ReportDisplayFormatter.examDateLabel($0) }
            let hint = "本粘贴含 \(visits.count) 次就诊（\(labels.joined(separator: "、"))），入库时将按日期拆分为 \(visitDates.count) 份报告，便于健康趋势对比。"
            recommendations.insert(hint, at: 0)
        }

        let examDate = visitDates.max() ?? parseExamDate(from: trimmed)

        return ReportAIService.StructuredExtraction(
            metrics: allMetrics,
            findings: allFindings,
            recommendations: recommendations,
            examDate: examDate
        )
    }

    // MARK: - Visit blocks

    private static func splitVisits(_ text: String) -> [VisitBlock] {
        let lines = text.components(separatedBy: .newlines)
        var blocks: [VisitBlock] = []
        var currentTitle = "门诊记录"
        var currentDate: Date?
        var currentLines: [String] = []

        func flush() {
            guard !currentLines.isEmpty else { return }
            blocks.append(VisitBlock(date: currentDate, title: currentTitle, lines: currentLines))
            currentLines = []
        }

        for line in lines {
            if let visit = parseVisitHeader(line) {
                flush()
                currentTitle = visit.title
                currentDate = visit.date
                continue
            }
            if isYearHeader(line) { continue }
            currentLines.append(line)
        }
        flush()

        if blocks.isEmpty {
            blocks.append(VisitBlock(date: parseExamDate(from: text), title: "门诊记录", lines: lines))
        }
        return blocks
    }

    private static func parseVisitHeader(_ line: String) -> (title: String, date: Date?)? {
        let trimmed = stripMarkdown(line).trimmingCharacters(in: CharacterSet.whitespaces)
        guard trimmed.hasPrefix("###") else { return nil }
        let body = trimmed.dropFirst(3).trimmingCharacters(in: CharacterSet.whitespaces)
        guard !body.isEmpty else { return nil }
        let date = parseDateToken(from: String(body))
        return (String(body), date)
    }

    private static func parseDateToken(from text: String) -> Date? {
        guard let regex = try? NSRegularExpression(pattern: #"(\d{4})-(\d{2})-(\d{2})"#),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else {
            return nil
        }
        func intGroup(_ i: Int) -> Int? {
            guard let range = Range(match.range(at: i), in: text) else { return nil }
            return Int(text[range])
        }
        guard let y = intGroup(1), let m = intGroup(2), let d = intGroup(3) else { return nil }
        return Calendar.current.date(from: DateComponents(year: y, month: m, day: d))
    }

    private static func isYearHeader(_ line: String) -> Bool {
        let t = stripMarkdown(line).trimmingCharacters(in: CharacterSet.whitespaces)
        return t.range(of: #"^##\s*\d{4}年"#, options: .regularExpression) != nil
    }

    // MARK: - Per-visit parse

    private struct VisitParseResult {
        let metrics: [ReportImporter.DraftMetric]
        let findings: [ReportImporter.DraftFinding]
        let recommendations: [String]
    }

    private static func parseVisit(_ visit: VisitBlock) -> VisitParseResult {
        var metrics: [ReportImporter.DraftMetric] = []
        var findings: [ReportImporter.DraftFinding] = []
        var recommendations: [String] = []
        var examSite = visit.title
        var mode: ParseMode = .general
        var currentPanel = ""

        for line in visit.lines {
            let indent = line.prefix(while: { $0 == " " || $0 == "\t" }).count
            let clean = normalizeLine(line)
            guard !clean.isEmpty else { continue }
            if isNoiseLine(clean) { continue }
            if isPanelHeaderLine(clean) {
                currentPanel = panelSectionTitle(for: clean)
                mode = .general
                continue
            }

            if let (label, value) = parseField(clean) {
                mode = .general
                switch label {
                case "检查部位":
                    examSite = value.isEmpty ? examSite : value
                case "检查描述":
                    if !value.isEmpty {
                        findings.append(imagingFinding(title: imagingTitle(examSite), detail: value))
                    }
                case "检查所见":
                    if !value.isEmpty { appendImagingFinding(value, into: &findings) }
                    mode = .inFindings
                case "诊断结论":
                    appendDiagnosis(value, examSite: examSite, findings: &findings, recommendations: &recommendations)
                default:
                    break
                }
                continue
            }

            if mode == .inFindings && (indent >= 2 || clean.hasPrefix("-")) {
                appendImagingFinding(normalizeLine(clean), into: &findings)
                continue
            }

            if let metric = HealthMetricLineParser.parse(clean, panelSection: currentPanel) {
                mode = .general
                metrics.append(metric)
            } else if let looseFinding = parseLooseFinding(clean) {
                findings.append(looseFinding)
            }
        }

        return VisitParseResult(metrics: metrics, findings: findings, recommendations: recommendations)
    }

    private static func stampVisitDate(_ result: VisitParseResult, date: Date?) -> VisitParseResult {
        guard let date else { return result }
        let metrics = result.metrics.map { item -> ReportImporter.DraftMetric in
            var copy = item
            copy.visitDate = date
            return copy
        }
        let findings = result.findings.map { item -> ReportImporter.DraftFinding in
            var copy = item
            copy.visitDate = date
            return copy
        }
        return VisitParseResult(metrics: metrics, findings: findings, recommendations: result.recommendations)
    }

    /// 无字段标签的自由文本结论（如「超声提示：…」「印象：…」）
    private static func parseLooseFinding(_ line: String) -> ReportImporter.DraftFinding? {
        let prefixes = ["超声提示", "超声印象", "印象", "提示", "诊断", "结论"]
        for prefix in prefixes {
            for sep in ["：", ":"] {
                let head = "\(prefix)\(sep)"
                guard line.hasPrefix(head) else { continue }
                let body = String(line.dropFirst(head.count)).trimmingCharacters(in: CharacterSet.whitespaces)
                guard body.count >= 4, !isJunkFindingTitle(body) else { return nil }
                return ReportImporter.DraftFinding(
                    category: "影像",
                    title: shortImagingTitle(body),
                    detail: body,
                    isAbnormal: isAbnormalImagingText(body)
                )
            }
        }
        return nil
    }

    /// 小节标题 → 报告章节名
    private static func panelSectionTitle(for line: String) -> String {
        let t = stripMarkdown(line).trimmingCharacters(in: CharacterSet.whitespaces)
        switch t {
        case "凝血功能": return "凝血功能"
        case "心脏标志物": return "心脏标志物"
        case "感染性标志物", "感染性标志物（病毒抗体）": return "感染标志物"
        case "生化": return "血液生化"
        case "血常规": return "血常规"
        case "甲状腺功能", "免疫组": return "甲状腺功能"
        default:
            if t.contains("甲状腺") { return "甲状腺功能" }
            if t.contains("凝血") { return "凝血功能" }
            if t.contains("心脏") { return "心脏标志物" }
            if t.contains("病毒") || t.contains("感染") { return "感染标志物" }
            return ""
        }
    }

    // MARK: - Rescan

    private static func rescanUnstructuredLines(
        _ text: String,
        existingMetrics: [ReportImporter.DraftMetric]
    ) -> [ReportImporter.DraftMetric] {
        let existingKeys = Set(existingMetrics.map { MetricNameCanonicalizer.canonicalKey(for: $0.name) })
        var found: [ReportImporter.DraftMetric] = []

        for rawLine in text.components(separatedBy: .newlines) {
            let clean = normalizeLine(rawLine)
            guard !clean.isEmpty, !isNoiseLine(clean), !isPanelHeaderLine(clean) else { continue }
            if parseField(clean) != nil { continue }
            guard let metric = HealthMetricLineParser.parse(clean) else { continue }
            let key = MetricNameCanonicalizer.canonicalKey(for: metric.name)
            guard !existingKeys.contains(key) else { continue }
            found.append(metric)
        }
        return found
    }

    // MARK: - Findings

    private static func imagingTitle(_ site: String) -> String {
        let s = site
        if s.contains("胸") || s.contains("肺") || s.contains("CT") { return "胸部影像" }
        if s.contains("腹") || s.contains("肝") || s.contains("MRI") { return "腹部影像" }
        if s.contains("甲状腺") { return "甲状腺" }
        return site.isEmpty ? "影像检查" : site
    }

    private static func imagingFinding(title: String, detail: String) -> ReportImporter.DraftFinding {
        ReportImporter.DraftFinding(
            category: "影像",
            title: title,
            detail: detail,
            isAbnormal: isAbnormalImagingText(detail)
        )
    }

    private static func appendImagingFinding(_ text: String, into findings: inout [ReportImporter.DraftFinding]) {
        let t = text.trimmingCharacters(in: CharacterSet.whitespaces)
        guard !isJunkFindingTitle(t) else { return }
        guard !ReportMetricNormalizer.isInsignificantImagingLine(t) else { return }

        let title = shortImagingTitle(t)
        let detail = (title == t || t.hasPrefix(title) && t.count - title.count < 4) ? "" : t
        findings.append(ReportImporter.DraftFinding(
            category: "影像",
            title: title,
            detail: detail,
            isAbnormal: isAbnormalImagingText(t)
        ))
    }

    private static func appendDiagnosis(
        _ text: String,
        examSite: String,
        findings: inout [ReportImporter.DraftFinding],
        recommendations: inout [String]
    ) {
        let category = examSite.contains("胸") || text.contains("肺") ? "影像" : "影像"
        let parts = text.split(whereSeparator: { "，,".contains($0) })
        for part in parts {
            let segment = String(part).trimmingCharacters(in: CharacterSet.whitespaces)
            guard segment.count >= 2 else { continue }
            if isRecommendationLike(segment) {
                recommendations.append(segment)
                continue
            }
            guard !ReportMetricNormalizer.isInsignificantImagingLine(segment) else { continue }
            let title = shortImagingTitle(segment)
            let detail = (title == segment) ? "" : segment
            findings.append(ReportImporter.DraftFinding(
                category: category,
                title: title,
                detail: detail,
                isAbnormal: isAbnormalImagingText(segment)
            ))
        }
    }

    private static func shortImagingTitle(_ text: String) -> String {
        if let range = text.range(of: "（", options: [], range: nil, locale: nil) {
            let head = String(text[..<range.lowerBound]).trimmingCharacters(in: CharacterSet.whitespaces)
            if head.count >= 2 { return String(head.prefix(24)) }
        }
        if text.count <= 24 { return text }
        return String(text.prefix(24)) + "…"
    }

    private static func isAbnormalImagingText(_ text: String) -> Bool {
        if ReportMetricNormalizer.isInsignificantImagingLine(text) { return false }
        if text.contains("结节") || text.contains("血管瘤") || text.contains("FNH") { return true }
        if text.contains("磨玻璃") || text.contains("占位") || text.contains("异常信号") { return true }
        return false
    }

    private static func isJunkFindingTitle(_ title: String) -> Bool {
        let t = stripMarkdown(title).trimmingCharacters(in: CharacterSet.whitespaces)
        if t.count < 3 { return true }
        if fieldLabels.contains(where: { t == $0 || t.hasPrefix("\($0)：") || t.hasPrefix("\($0):") }) { return true }
        if t.hasPrefix("*注") || t.hasPrefix("注：") { return true }
        if t.contains("参考区间显示") || t.contains("暂按报告原文") { return true }
        if t.hasPrefix("#") { return true }
        if t.hasPrefix("---") { return true }
        return false
    }

    // MARK: - Metrics (legacy wrapper)

    private static func parseClinicMetricLine(_ line: String) -> ReportImporter.DraftMetric? {
        HealthMetricLineParser.parse(line)
    }

    private static func dedupeMetrics(_ metrics: [ReportImporter.DraftMetric], visitCount: Int = 1) -> [ReportImporter.DraftMetric] {
        guard visitCount <= 1 else { return metrics }
        var seen = Set<String>()
        return metrics.filter { item in
            let key = MetricNameCanonicalizer.canonicalKey(for: item.name)
            guard !seen.contains(key) else { return false }
            seen.insert(key)
            return true
        }
    }

    // MARK: - Line helpers

    private static func normalizeLine(_ line: String) -> String {
        var s = line.trimmingCharacters(in: CharacterSet.whitespaces)
        while s.hasPrefix("- ") || s.hasPrefix("* ") || s.hasPrefix("• ") || s.hasPrefix("· ") {
            s = String(s.dropFirst(2)).trimmingCharacters(in: CharacterSet.whitespaces)
        }
        return stripMarkdown(s).trimmingCharacters(in: CharacterSet.whitespaces)
    }

    private static func stripMarkdown(_ text: String) -> String {
        text
            .replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "__", with: "")
            .trimmingCharacters(in: CharacterSet.whitespaces)
    }

    private static func parseField(_ line: String) -> (String, String)? {
        let clean = stripMarkdown(line).trimmingCharacters(in: CharacterSet.whitespaces)
        for label in fieldLabels {
            let prefixes = ["\(label)：", "\(label):"]
            for prefix in prefixes where clean.hasPrefix(prefix) {
                let value = String(clean.dropFirst(prefix.count)).trimmingCharacters(in: CharacterSet.whitespaces)
                return (label, value)
            }
            if clean == label { return (label, "") }
        }
        return nil
    }

    private static func isPanelHeaderLine(_ line: String) -> Bool {
        let t = stripMarkdown(line).trimmingCharacters(in: CharacterSet.whitespaces)
        if panelHeaders.contains(t) { return true }
        return ReportMetricNormalizer.isPanelHeader(t)
    }

    private static func isNoiseLine(_ line: String) -> Bool {
        let t = stripMarkdown(line).trimmingCharacters(in: CharacterSet.whitespaces)
        if t.isEmpty { return true }
        if t == "---" { return true }
        if t.hasPrefix("*注") || t.hasPrefix("注：") { return true }
        if t.contains("参考区间显示明显有误") || t.contains("暂按报告原文录入") { return true }
        if t.hasPrefix("##") { return true }
        return false
    }

    private static func normalizeSuperscripts(_ text: String) -> String {
        let map: [Character: Character] = [
            "⁰": "0", "¹": "1", "²": "2", "³": "3", "⁴": "4",
            "⁵": "5", "⁶": "6", "⁷": "7", "⁸": "8", "⁹": "9"
        ]
        var result = ""
        for char in text {
            result.append(map[char] ?? char)
        }
        return result
            .replacingOccurrences(of: "×10", with: "×10^")
            .replacingOccurrences(of: "x10", with: "×10^")
    }

    // MARK: - Recommendations & date

    private static func parseRecommendations(from text: String) -> [String] {
        var results: [String] = []
        for line in text.components(separatedBy: .newlines) {
            let trimmed = normalizeLine(line)
            guard trimmed.count >= 4 else { continue }
            if isRecommendationLike(trimmed) {
                results.append(trimmed)
            }
        }
        return Array(results.prefix(8))
    }

    private static func isRecommendationLike(_ text: String) -> Bool {
        text.contains("建议") || text.contains("复查") || text.contains("随访")
            || text.contains("普美显") || text.contains("相仿")
    }

    private static func parseExamDate(from text: String) -> Date? {
        if let visit = parseDateToken(from: text) { return visit }
        let pattern = #"(?:就诊|检查|体检|采样)?日期[:：]?\s*(\d{4})[年\-/.](\d{1,2})[月\-/.](\d{1,2})"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else {
            return fallbackExamDate(from: text)
        }
        func intGroup(_ i: Int) -> Int? {
            guard let range = Range(match.range(at: i), in: text) else { return nil }
            return Int(text[range])
        }
        guard let y = intGroup(1), let m = intGroup(2), let d = intGroup(3) else { return nil }
        return Calendar.current.date(from: DateComponents(year: y, month: m, day: d))
    }

    private static func fallbackExamDate(from text: String) -> Date? {
        parseDateToken(from: text)
    }
}