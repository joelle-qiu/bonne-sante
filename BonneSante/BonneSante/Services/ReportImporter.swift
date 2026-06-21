import Foundation
import UIKit
import Vision
import PDFKit

/// Apple Vision OCR + 本地表格解析 + DeepSeek 文本整理（不上传原图）
/// @author jiali.qiu
enum ReportImporter {

    struct DraftMetric: Identifiable, Equatable {
        let id: UUID
        var name: String
        var valueText: String
        var value: Double
        var unit: String
        var referenceRange: String
        var isAbnormal: Bool
        /// 报告章节（一般检查 / 血常规 / 影像检查 等）
        var section: String
        /// 所属就诊日期（多 visit 粘贴时用于拆分入库）
        var visitDate: Date?
        /// 异常严重度 1–5（5 最高），由 DeepSeek 或本地规则填充
        var severityRank: Int
        /// 简要临床判断依据（供档案与趋势展示）
        var assessmentNote: String
        /// 所属检验组合名（校对页分组展示；入库后各子项独立存储）
        var panelName: String

        init(
            id: UUID = UUID(),
            name: String,
            valueText: String,
            value: Double = 0,
            unit: String = "",
            referenceRange: String = "",
            isAbnormal: Bool = false,
            section: String = "",
            visitDate: Date? = nil,
            severityRank: Int = 0,
            assessmentNote: String = "",
            panelName: String = ""
        ) {
            self.id = id
            self.name = name
            self.valueText = valueText
            self.value = value
            self.unit = unit
            self.referenceRange = referenceRange
            self.isAbnormal = isAbnormal
            self.section = section.isEmpty
                ? ReportMetricCategory.inferSection(name: name, valueText: valueText)
                : section
            self.visitDate = visitDate
            self.severityRank = severityRank
            self.assessmentNote = assessmentNote
            self.panelName = panelName
        }
    }

    struct DraftFinding: Identifiable, Equatable {
        let id: UUID
        var category: String
        var title: String
        var detail: String
        var isAbnormal: Bool
        var visitDate: Date?
        var severityRank: Int
        var assessmentNote: String
        /// 诊断结论（如「正常心电图」「未见明显异常」），与 detail 中的测量参数分开存放
        var conclusion: String
        /// 形态标签（DeepSeek 标注，如 cyst / hemangioma）
        var morphology: String
        /// 部位标签（DeepSeek 标注，如 cervix / liver）
        var organSite: String
        /// 附加形态标签（可选）
        var morphologyTags: [String]
        /// DeepSeek 显式输出的趋势主径（mm），优先于 detail 正则解析
        var primarySizeMm: Double?
        /// 次要灶尺寸（mm），如 FNH、微小结节范围上限
        var secondarySizeMm: Double?
        /// 肺结节 CT 值（Hu），仅肺结节使用
        var ctValueHu: Int?

        init(
            id: UUID = UUID(),
            category: String = "其他",
            title: String,
            detail: String = "",
            isAbnormal: Bool = true,
            visitDate: Date? = nil,
            severityRank: Int = 0,
            assessmentNote: String = "",
            conclusion: String = "",
            morphology: String = "",
            organSite: String = "",
            morphologyTags: [String] = [],
            primarySizeMm: Double? = nil,
            secondarySizeMm: Double? = nil,
            ctValueHu: Int? = nil
        ) {
            self.id = id
            self.category = category
            self.title = title
            self.detail = detail
            self.isAbnormal = isAbnormal
            self.visitDate = visitDate
            self.severityRank = severityRank
            self.assessmentNote = assessmentNote
            self.conclusion = conclusion
            self.morphology = morphology
            self.organSite = organSite
            self.morphologyTags = morphologyTags
            self.primarySizeMm = primarySizeMm
            self.secondarySizeMm = secondarySizeMm
            self.ctValueHu = ctValueHu
        }

        var taxonomyTags: ClinicalFindingTaxonomy.Tags {
            ClinicalFindingTaxonomy.parseTags(
                morphology: morphology,
                organSite: organSite,
                morphologyTags: morphologyTags
            )
        }
    }

    struct ImportDraft {
        var fileName: String
        var sourceType: String
        var rawText: String
        var metrics: [DraftMetric]
        var findings: [DraftFinding]
        var recommendations: [String]
        var examDate: Date?
        var assessmentSummary: String = ""
        var usedAIAssist: Bool
        var sanitizedPreview: String

        /// 指标与结论中出现的不同就诊日期（用于拆分入库）
        var distinctVisitDates: [Date] {
            let dates = metrics.compactMap(\.visitDate) + findings.compactMap(\.visitDate)
            let normalized = dates.map { Calendar.current.startOfDay(for: $0) }
            return Array(Set(normalized)).sorted()
        }
    }

    enum ImportError: LocalizedError {
        case unreadableImage
        case unreadablePDF
        case noTextRecognized

        var errorDescription: String? {
            switch self {
            case .unreadableImage: return "无法读取图片"
            case .unreadablePDF: return "无法读取 PDF"
            case .noTextRecognized: return "未识别到文字，请换一张更清晰的报告或手动添加指标"
            }
        }
    }

    private static let pdfRenderWidth: CGFloat = 2400

    private static let skipLineKeywords = [
        "项目名称", "结果", "参考值", "单位", "提示", "检验报告", "体检报告",
        "报告编号", "检验者", "审核者", "本报告", "咨询电话", "初步意见",
        "检查医生", "审核医生", "审核时间", "第", "页/共"
    ]

    // MARK: - Public

    static func importImage(
        _ image: UIImage,
        fileName: String,
        onProgress: ReportImportProgressHandler? = nil
    ) async throws -> ImportDraft {
        await ReportImportProgressReporter.emit(onProgress, 0.1, "正在 OCR 识别文字…")
        let lines = try await recognizeLayoutLines(in: image)
        let text = lines.map(\.text).joined(separator: "\n")
        guard !text.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).isEmpty else {
            throw ImportError.noTextRecognized
        }
        return await enrichDraft(
            fileName: fileName,
            sourceType: "screenshot",
            rawText: text,
            layoutLines: lines,
            pageTexts: [text],
            onProgress: onProgress
        )
    }

    static func importPDF(
        at url: URL,
        onProgress: ReportImportProgressHandler? = nil
    ) async throws -> ImportDraft {
        guard let document = PDFDocument(url: url) else {
            throw ImportError.unreadablePDF
        }

        var allLines: [LayoutLine] = []
        var pageTexts: [String] = []
        let pageCount = max(document.pageCount, 1)

        for index in 0..<document.pageCount {
            await ReportImportProgressReporter.emit(
                onProgress,
                0.08 + Double(index) / Double(pageCount) * 0.28,
                "正在 OCR 第 \(index + 1)/\(pageCount) 页…"
            )
            guard let page = document.page(at: index) else { continue }
            let image = renderPageImage(page)
            if let pageLines = try? await recognizeLayoutLines(in: image) {
                allLines.append(contentsOf: pageLines)
                pageTexts.append(pageLines.map(\.text).joined(separator: "\n"))
            }
        }

        let text = allLines.map(\.text).joined(separator: "\n")
        guard !text.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).isEmpty else {
            throw ImportError.noTextRecognized
        }

        return await enrichDraft(
            fileName: url.lastPathComponent,
            sourceType: "pdf",
            rawText: text,
            layoutLines: allLines,
            pageTexts: pageTexts,
            onProgress: onProgress
        )
    }

    // MARK: - Pipeline

    private static func enrichDraft(
        fileName: String,
        sourceType: String,
        rawText: String,
        layoutLines: [LayoutLine],
        pageTexts: [String],
        onProgress: ReportImportProgressHandler? = nil
    ) async -> ImportDraft {
        await ReportImportProgressReporter.emit(onProgress, 0.38, "正在本地解析表格…")
        let sections = buildTextSections(from: pageTexts, fullText: rawText)
        var localMetrics = ReportMetricNormalizer.filterMetrics(
            parseMetrics(from: rawText, layoutLines: layoutLines)
        )
        var localFindings = parseLocalFindings(from: sections.summary + "\n" + sections.imaging)
        var recommendations = parseLocalRecommendations(from: sections.summary)
        var usedAI = false

        if APIKeyManager.isReportAIAssistEnabled, APIKeyManager.isDeepSeekConfigured {
            await ReportImportProgressReporter.emit(onProgress, 0.55, "正在 DeepSeek 结构化…")
            if let ai = try? await ReportAIService.extractStructuredReport(from: sections),
               !ai.metrics.isEmpty || !ai.findings.isEmpty {
                let aiMetrics = ReportMetricNormalizer.filterMetrics(ai.metrics)
                // AI 结果足够时以 AI 为主，避免本地 OCR 噪声（审核时间、组合标题等）
                if aiMetrics.count >= 10 {
                    localMetrics = aiMetrics
                } else {
                    localMetrics = ReportMetricNormalizer.filterMetrics(
                        mergeMetrics(primary: aiMetrics, secondary: localMetrics)
                    )
                }
                localFindings = ReportMetricNormalizer.dedupeFindings(
                    mergeFindings(primary: ai.findings, secondary: localFindings)
                )
                if !ai.recommendations.isEmpty {
                    recommendations = ai.recommendations
                }
                usedAI = true
            }
        }

        localFindings = ReportMetricNormalizer.dedupeFindings(localFindings)

        let preview = ReportAIService.sanitizeForCloud(rawText)

        await ReportImportProgressReporter.emit(onProgress, 0.88, "正在对齐历史档案…")
        let draft = HealthRecordAligner.align(draft: ImportDraft(
            fileName: fileName,
            sourceType: sourceType,
            rawText: rawText,
            metrics: localMetrics,
            findings: localFindings,
            recommendations: recommendations,
            examDate: parseExamDate(from: rawText),
            usedAIAssist: usedAI,
            sanitizedPreview: preview
        ))
        await ReportImportProgressReporter.emit(onProgress, 1.0, "解析完成，进入校对…")
        return draft
    }

    private static func mergeMetrics(
        primary: [DraftMetric],
        secondary: [DraftMetric]
    ) -> [DraftMetric] {
        var merged = primary
        var names = Set(primary.map { ReportMetricNormalizer.normalizeName($0.name).lowercased() })
        for item in secondary {
            let key = ReportMetricNormalizer.normalizeName(item.name).lowercased()
            guard !names.contains(key) else { continue }
            names.insert(key)
            merged.append(item)
        }
        return merged
    }

    private static func mergeFindings(
        primary: [DraftFinding],
        secondary: [DraftFinding]
    ) -> [DraftFinding] {
        var merged = primary
        var titles = Set(primary.map { $0.title.lowercased() })
        for item in secondary {
            let key = item.title.lowercased()
            guard !titles.contains(key) else { continue }
            titles.insert(key)
            merged.append(item)
        }
        return merged
    }

    static func buildTextSections(from pageTexts: [String], fullText: String) -> ReportAIService.TextSections {
        var summary = ""
        var lab = ""
        var imaging = ""

        for page in pageTexts {
            if page.contains("异常检查结果") || page.contains("本次体检结果及建议") || page.contains("建 议") || page.contains("建议：") {
                summary += page + "\n"
            }
            if page.contains("项目名称") && (page.contains("参考值") || page.contains("结果")) {
                lab += page + "\n"
            }
            if page.contains("检查所见") || page.contains("检查结论") || page.contains("检查报告") {
                imaging += page + "\n"
            }
        }

        if summary.isEmpty, let range = fullText.range(of: "异常检查结果") {
            let tail = fullText[range.lowerBound...]
            summary = String(tail.prefix(2500))
        }

        return ReportAIService.TextSections(
            summary: summary,
            labTables: lab,
            imaging: imaging,
            fullText: fullText
        )
    }

    // MARK: - PDF Render

    private static func renderPageImage(_ page: PDFPage) -> UIImage {
        let rect = page.bounds(for: .mediaBox)
        let scale = pdfRenderWidth / max(rect.width, 1)
        let size = CGSize(width: rect.width * scale, height: rect.height * scale)
        return page.thumbnail(of: size, for: .mediaBox)
    }

    // MARK: - Layout OCR

    private struct LayoutLine {
        var text: String
        var midY: CGFloat
        var minX: CGFloat
        var segments: [String]
    }

    private static func recognizeLayoutLines(in image: UIImage) async throws -> [LayoutLine] {
        guard let cgImage = image.cgImage else { throw ImportError.unreadableImage }

        struct Obs {
            let text: String
            let midY: CGFloat
            let minX: CGFloat
        }

        let observations: [Obs] = try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let results = request.results as? [VNRecognizedTextObservation] ?? []
                let mapped = results.compactMap { obs -> Obs? in
                    guard let text = obs.topCandidates(1).first?.string else { return nil }
                    let box = obs.boundingBox
                    return Obs(
                        text: text.trimmingCharacters(in: CharacterSet.whitespaces),
                        midY: box.midY,
                        minX: box.minX
                    )
                }
                continuation.resume(returning: mapped)
            }
            request.recognitionLevel = .accurate
            request.recognitionLanguages = ["zh-Hans", "en-US"]
            request.usesLanguageCorrection = true

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }

        let sorted = observations.sorted {
            if abs($0.midY - $1.midY) > 0.012 { return $0.midY > $1.midY }
            return $0.minX < $1.minX
        }

        var rows: [[Obs]] = []
        for obs in sorted {
            if let lastIndex = rows.indices.last,
               abs(rows[lastIndex][0].midY - obs.midY) <= 0.012 {
                rows[lastIndex].append(obs)
            } else {
                rows.append([obs])
            }
        }

        return rows.map { row in
            let ordered = row.sorted { $0.minX < $1.minX }
            let segments = ordered.map(\.text)
            let joined = segments.joined(separator: " ")
            let first = ordered.first
            return LayoutLine(
                text: joined,
                midY: first?.midY ?? 0,
                minX: first?.minX ?? 0,
                segments: segments
            )
        }
    }

    // MARK: - Local narrative parsing

    private static func parseLocalFindings(from text: String) -> [DraftFinding] {
        var results: [DraftFinding] = []
        let checks: [(String, String)] = [
            ("双乳房小叶增生", "影像"),
            ("乳房小叶增生", "影像"),
            ("子宫肌瘤", "妇科"),
            ("宫颈糜烂样改变", "妇科"),
            ("宫颈糜烂", "妇科"),
            ("肺结节", "影像"),
            ("脓细胞升高", "检验")
        ]
        for (keyword, category) in checks where text.contains(keyword) {
            guard !results.contains(where: { $0.title.contains(keyword) || keyword.contains($0.title) }) else { continue }
            results.append(DraftFinding(category: category, title: keyword, detail: "", isAbnormal: true))
        }
        if let mm = text.range(of: #"(\d+)\s*[×x]\s*(\d+)\s*[×x]\s*(\d+)\s*mm"#, options: .regularExpression) {
            let size = String(text[mm])
            if let idx = results.firstIndex(where: { $0.title.contains("子宫肌瘤") }) {
                results[idx].detail = size
            } else {
                results.append(DraftFinding(category: "妇科", title: "子宫肌瘤", detail: size, isAbnormal: true))
            }
        }
        return results
    }

    private static func parseLocalRecommendations(from summary: String) -> [String] {
        guard let range = summary.range(of: "建 议") ?? summary.range(of: "建议：") else { return [] }
        let tail = String(summary[range.upperBound...])
        return tail
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: CharacterSet.whitespaces) }
            .filter { $0.count > 6 && !$0.contains("报告医生") && !$0.contains("主检医生") }
            .prefix(8)
            .map { String($0) }
    }

    // MARK: - Parsing

    static func buildDraft(fileName: String, sourceType: String, rawText: String) -> ImportDraft {
        ImportDraft(
            fileName: fileName,
            sourceType: sourceType,
            rawText: rawText,
            metrics: parseMetrics(from: rawText).map { ReportMetricNormalizer.polish($0) },
            findings: [],
            recommendations: [],
            examDate: parseExamDate(from: rawText),
            usedAIAssist: false,
            sanitizedPreview: ReportAIService.sanitizeForCloud(rawText)
        )
    }

    static func parseMetrics(from text: String) -> [DraftMetric] {
        parseMetrics(from: text, layoutLines: [])
    }

    private static func parseMetrics(from text: String, layoutLines: [LayoutLine]) -> [DraftMetric] {
        var results: [DraftMetric] = []
        var seen = Set<String>()

        for line in layoutLines {
            if shouldSkip(line.text) { continue }
            if let metric = parseRenjiTableRow(segments: line.segments, fullLine: line.text)
                ?? parseTableRow(segments: line.segments, fullLine: line.text)
                ?? parseLine(line.text) {
                let key = ReportMetricNormalizer.normalizeName(metric.name).lowercased()
                guard ReportMetricNormalizer.isLikelyLabMetricName(metric.name), !seen.contains(key) else { continue }
                seen.insert(key)
                results.append(metric)
            }
        }

        for line in text.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: CharacterSet.whitespaces)
            guard trimmed.count >= 3, !shouldSkip(trimmed) else { continue }
            if let metric = parseLine(trimmed) {
                let key = ReportMetricNormalizer.normalizeName(metric.name).lowercased()
                guard ReportMetricNormalizer.isLikelyLabMetricName(metric.name), !seen.contains(key) else { continue }
                seen.insert(key)
                results.append(metric)
            }
        }

        return results
    }

    /// 仁济等五列表格：项目名 | 结果 | 参考值 | 单位 | 提示
    private static func parseRenjiTableRow(segments: [String], fullLine: String) -> DraftMetric? {
        guard segments.count >= 3 else { return nil }
        if fullLine.contains("审核者") || fullLine.contains("审校者") { return nil }

        let nameCandidate = segments[0]
        guard ReportMetricNormalizer.isLikelyLabMetricName(nameCandidate),
              !ReportMetricNormalizer.isPanelHeader(nameCandidate) else { return nil }

        var valueIndex: Int?
        var value: Double?
        for (index, segment) in segments.enumerated() where index > 0 {
            if let v = extractNumber(from: segment) {
                valueIndex = index
                value = v
                break
            }
        }
        guard let idx = valueIndex, let val = value else { return nil }

        let valueSegment = segments[idx]
        let trailing = Array(segments.dropFirst(idx + 1))
        let unit = trailing.first(where: { looksLikeUnit($0) || isKnownUnitFragment($0) }) ?? ""
        let ref = trailing.first(where: { looksLikeReference($0) }) ?? ""
        let abnormal = fullLine.contains("↑") || fullLine.contains("↓") || fullLine.contains(" H")
            || fullLine.contains(" L") || fullLine.contains("忄") || fullLine.contains("偏高")

        let valueText: String
        if unit.isEmpty {
            valueText = valueSegment
        } else {
            valueText = "\(valueSegment) \(ReportMetricNormalizer.normalizeUnit(unit))"
        }

        var metric = DraftMetric(
            name: ReportMetricNormalizer.normalizeName(nameCandidate),
            valueText: valueText,
            value: val,
            unit: ReportMetricNormalizer.normalizeUnit(unit),
            referenceRange: ref,
            isAbnormal: abnormal
        )
        return ReportMetricNormalizer.polish(metric, lineHint: fullLine)
    }

    private static func parseTableRow(segments: [String], fullLine: String) -> DraftMetric? {
        parseRenjiTableRow(segments: segments, fullLine: fullLine)
    }

    private static func parseLine(_ line: String) -> DraftMetric? {
        if shouldSkip(line) { return nil }
        if line.contains("审核者") || line.contains("审校者") { return nil }
        if ReportMetricNormalizer.isTimestampLike(line) { return nil }

        let patterns = [
            #"^([\u4e00-\u9fa5A-Za-zγ\-（）()·]+?)\s+([\d.]+)\s*([↑↓HL])?\s*(.*)$"#,
            #"^([\u4e00-\u9fa5A-Za-zγ\-（）()·]{2,})\s*[:：]?\s*([\d.]+)\s*([a-zA-Z/%μµ°·×/\^\-]+)?"#
        ]

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) else {
                continue
            }

            func group(_ i: Int) -> String {
                guard i < match.numberOfRanges else { return "" }
                let nsRange = match.range(at: i)
                guard nsRange.location != NSNotFound,
                      let range = Range(nsRange, in: line) else { return "" }
                return String(line[range]).trimmingCharacters(in: CharacterSet.whitespaces)
            }

            let name = ReportMetricNormalizer.normalizeName(group(1))
            guard ReportMetricNormalizer.isLikelyLabMetricName(name) else { continue }

            let valueText = group(2)
            guard let value = Double(valueText) else { continue }

            let markerOrUnit = group(3)
            let tail = group(4)
            let unit = markerOrUnit.range(of: #"^[a-zA-Z/%μµ]"#, options: .regularExpression) != nil
                ? ReportMetricNormalizer.normalizeUnit(markerOrUnit)
                : extractUnit(from: tail.isEmpty ? line : tail)
            let abnormal = line.contains("↑") || line.contains("↓") || line.contains("偏高") || line.contains("偏低")
                || line.contains(" H") || line.contains(" L") || markerOrUnit == "H" || markerOrUnit == "L"

            return ReportMetricNormalizer.polish(
                DraftMetric(
                    name: name,
                    valueText: unit.isEmpty ? valueText : "\(valueText) \(unit)",
                    value: value,
                    unit: unit,
                    referenceRange: extractReferenceRange(from: line),
                    isAbnormal: abnormal
                ),
                lineHint: line
            )
        }
        return nil
    }

    private static func shouldSkip(_ line: String) -> Bool {
        if line.count < 2 { return true }
        if skipLineKeywords.contains(where: { line.contains($0) && line.count < 24 }) { return true }
        if line.allSatisfy({ $0.isNumber || $0 == "." || $0 == " " }) { return true }
        if line.contains("健康就是幸福") || line.contains("上海交通大学") { return true }
        return false
    }

    private static func extractNumber(from text: String) -> Double? {
        let cleaned = text.replacingOccurrences(of: "↑", with: "")
            .replacingOccurrences(of: "↓", with: "")
            .replacingOccurrences(of: "忄", with: "")
            .trimmingCharacters(in: CharacterSet.whitespaces)
        guard let match = cleaned.range(of: #"^[\d.]+"#, options: .regularExpression) else { return nil }
        return Double(cleaned[match])
    }

    private static func looksLikeUnit(_ text: String) -> Bool {
        let t = text.lowercased()
        return t.range(of: #"^(u/l|mmol/l|μmol/l|g/l|×10|au/ml|ng/ml|mmhg|/ep|%|mm/h)"#, options: .regularExpression) != nil
    }

    private static func isKnownUnitFragment(_ text: String) -> Bool {
        let lower = text.lowercased()
        return lower.contains("mol/l") || lower.contains("u/l") || lower.contains("mmhg") || lower.contains("/ep")
    }

    private static func looksLikeReference(_ text: String) -> Bool {
        text.contains("-") || text.contains("～") || text.contains("~") || text.contains("<") || text.contains(">")
            || text.range(of: #"[\d.]+\s*[-~～]\s*[\d.]+"#, options: .regularExpression) != nil
    }

    private static func extractUnit(from tail: String) -> String {
        let units = ["U/L", "mmol/L", "μmol/L", "g/L", "AU/mL", "ng/mL", "×10^9/L", "×10^12/L", "%", "mmHg", "/EP"]
        if let found = units.first(where: { tail.localizedCaseInsensitiveContains($0) }) {
            return found
        }
        return ReportMetricNormalizer.extractAndFixUnit(from: tail, explicitUnit: "")
    }

    private static func extractReferenceRange(from line: String) -> String {
        if let range = line.range(of: #"[\(（][^)）]+[\)）]"#, options: .regularExpression) {
            return String(line[range]).trimmingCharacters(in: CharacterSet(charactersIn: "()（）"))
        }
        if let range = line.range(of: #"[\d.]+\s*[-~～]\s*[\d.]+"#, options: .regularExpression) {
            return String(line[range])
        }
        if let range = line.range(of: #"[<>≤≥]\s*[\d.]+"#, options: .regularExpression) {
            return String(line[range])
        }
        return ""
    }

    private static func parseExamDate(from text: String) -> Date? {
        let pattern = #"(\d{4})[年\-/.](\d{1,2})[月\-/.](\d{1,2})"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
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
}
