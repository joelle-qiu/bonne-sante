import Foundation

/// 解析用户从 DeepSeek 网页复制粘贴的结构化 JSON
/// @author jiali.qiu
enum ReportPasteImporter {

    enum PasteError: LocalizedError {
        case empty
        case invalidJSON
        case noContent

        var errorDescription: String? {
            switch self {
            case .empty: return "请粘贴 DeepSeek 返回的内容"
            case .invalidJSON: return "无法识别 JSON，请确认 DeepSeek 按指令输出了完整 JSON"
            case .noContent: return "未能解析出内容。请粘贴 DeepSeek 返回的 JSON，或 CT/MRI 随访片段（findings 数组 + recommendations），或使用下方「智能修复」重试"
            }
        }
    }

    /// 分段导入载荷（仅解析，对齐在校对前按段执行）
    struct StagedSegmentPayload: Identifiable {
        let id = UUID()
        let extraction: ReportAIService.StructuredExtraction
        let label: String
        let previewText: String
    }

  enum PasteImportOutcome {
        case single(ReportImporter.ImportDraft)
        case staged([StagedSegmentPayload])
    }

    private static let largeSourceThreshold = 32_768
    private static let aiEnrichMaxItems = 64
    private static let stagedAlignThreshold = 80

    /// 将粘贴文本转为 ImportDraft（本地解析 + 严重度兜底）
    static func importFromPaste(_ text: String) throws -> ReportImporter.ImportDraft {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw PasteError.empty }

        let extraction = ReportPasteParser.parse(trimmed)
        guard !extraction.isEmpty else {
            if trimmed.contains("{") || trimmed.contains("[") {
                throw PasteError.noContent
            }
            throw PasteError.invalidJSON
        }

        let assembled = assembleDraft(from: extraction, sourceText: trimmed)
        let aligned = HealthRecordAligner.align(draft: assembled)
        return ReportAIService.applyLocalSeverityRanking(aligned)
    }

    /// 异步解析；多段 JSON 返回 staged，单段返回 single（含对齐）
    static func importFromPasteAsync(
        _ text: String,
        onProgress: ReportImportProgressHandler? = nil
    ) async throws -> PasteImportOutcome {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw PasteError.empty }

        let sourceBytes = trimmed.utf8.count
        await ReportImportProgressReporter.emit(onProgress, 0.12, "正在解析 JSON…")

        let segments = await Task.detached(priority: .userInitiated) {
            ReportPasteParser.parseSegments(trimmed)
        }.value

        await ReportImportProgressReporter.emit(
            onProgress,
            0.28,
            segments.isEmpty ? "正在解析 JSON…" : "已识别 \(segments.count) 段报告…"
        )

        guard !segments.isEmpty else {
            if trimmed.contains("{") || trimmed.contains("[") {
                throw PasteError.noContent
            }
            throw PasteError.invalidJSON
        }

        let totalItems = segments.reduce(0) { $0 + $1.metrics.count + $1.findings.count }
        let shouldStage = segments.count >= 2
            || (segments.count == 1 && totalItems > stagedAlignThreshold && sourceBytes > 16_384)

        if shouldStage {
            await ReportImportProgressReporter.emit(
                onProgress,
                0.55,
                "检测到 \(segments.count) 段报告，将分段校对入库…"
            )
            let payloads = segments.enumerated().map { index, extraction in
                let label = ReportPasteParser.segmentLabel(from: extraction)
                let preview = segmentPreviewText(
                    label: label,
                    index: index + 1,
                    total: segments.count,
                    extraction: extraction
                )
                return StagedSegmentPayload(
                    extraction: extraction,
                    label: label,
                    previewText: preview
                )
            }
            await ReportImportProgressReporter.emit(onProgress, 1.0, "解析完成，进入分段校对…")
            return .staged(payloads)
        }

        let extraction = segments[0]
        await ReportImportProgressReporter.emit(onProgress, 0.38, "正在对齐档案指标…")
        let draft = await finalizeDraft(
            from: extraction,
            sourceText: trimmed,
            sourceBytes: sourceBytes,
            onProgress: onProgress,
            progressBase: 0.38
        )
        await ReportImportProgressReporter.emit(onProgress, 1.0, "解析完成，进入校对…")
        return .single(draft)
    }

    /// 单段对齐 + 严重度（分段流程在校对前调用）
    static func prepareDraftForVerify(
        from payload: StagedSegmentPayload,
        onProgress: ReportImportProgressHandler? = nil
    ) async -> ReportImporter.ImportDraft {
        await ReportImportProgressReporter.emit(onProgress, 0.15, "正在整理本段指标…")
        let extraction = ReportAIService.finalizeExtraction(payload.extraction)
        let assembled = assembleDraft(
            from: extraction,
            sourceText: payload.previewText,
            imagingHint: payload.previewText.contains("影像")
        )
        await ReportImportProgressReporter.emit(onProgress, 0.35, "正在对齐本段指标…")
        let draft = await Task.detached(priority: .userInitiated) {
            let aligned = HealthRecordAligner.align(draft: assembled)
            return ReportAIService.applyLocalSeverityRanking(aligned)
        }.value
        await ReportImportProgressReporter.emit(onProgress, 1.0, "本段已就绪")
        return draft
    }

    private static func finalizeDraft(
        from extraction: ReportAIService.StructuredExtraction,
        sourceText: String,
        sourceBytes: Int,
        onProgress: ReportImportProgressHandler?,
        progressBase: Double
    ) async -> ReportImporter.ImportDraft {
        let finalized = ReportAIService.finalizeExtraction(extraction)
        let assembled = assembleDraft(from: finalized, sourceText: sourceText)
        var draft = await Task.detached(priority: .userInitiated) {
            let aligned = HealthRecordAligner.align(draft: assembled)
            return ReportAIService.applyLocalSeverityRanking(aligned)
        }.value

        if shouldRunAIEnrichment(for: draft, sourceBytes: sourceBytes) {
            await ReportImportProgressReporter.emit(
                onProgress,
                progressBase + 0.2,
                "正在 AI 标注严重度…"
            )
            draft = await ReportAIService.enrichDraftRanking(draft)
            draft.usedAIAssist = APIKeyManager.isReportAIAssistEnabled && APIKeyManager.isDeepSeekConfigured
        } else {
            await ReportImportProgressReporter.emit(
                onProgress,
                progressBase + 0.2,
                "大文件：使用本地严重度规则…"
            )
            draft.usedAIAssist = false
        }
        return draft
    }

    private static func segmentPreviewText(
        label: String,
        index: Int,
        total: Int,
        extraction: ReportAIService.StructuredExtraction
    ) -> String {
        "分段导入 \(index)/\(total) · \(label)（\(extraction.metrics.count) 项指标 · \(extraction.findings.count) 项结论）"
    }

    /// 仅组装草稿，不做对齐/严重度（供后台线程调用）
    private static func assembleDraft(
        from extraction: ReportAIService.StructuredExtraction,
        sourceText: String,
        imagingHint: Bool? = nil
    ) -> ReportImporter.ImportDraft {
        let isImaging = imagingHint ?? ImagingFollowUpEnricher.isImagingFollowUpPaste(sourceText)
        return ReportImporter.ImportDraft(
            fileName: ReportDisplayFormatter.preferredFileName(
                examDate: extraction.examDate,
                original: isImaging ? "CT/MRI 影像随访" : "DeepSeek 整理结果"
            ),
            sourceType: "deepseek_paste",
            rawText: ReportPasteParser.compactStorageText(for: sourceText),
            metrics: categorizedMetrics(extraction.metrics),
            findings: ReportMetricNormalizer.dedupeFindings(extraction.findings),
            recommendations: extraction.recommendations,
            examDate: extraction.examDate,
            assessmentSummary: extraction.assessmentSummary,
            usedAIAssist: false,
            sanitizedPreview: ""
        )
    }

    private static func shouldRunAIEnrichment(for draft: ReportImporter.ImportDraft, sourceBytes: Int) -> Bool {
        guard APIKeyManager.isReportAIAssistEnabled, APIKeyManager.isDeepSeekConfigured else {
            return false
        }
        let itemCount = draft.metrics.count + draft.findings.count
        if sourceBytes > largeSourceThreshold { return false }
        if itemCount > aiEnrichMaxItems { return false }
        return true
    }

    private static func categorizedMetrics(_ metrics: [ReportImporter.DraftMetric]) -> [ReportImporter.DraftMetric] {
        metrics.map { item in
            var copy = item
            ReportMetricCategory.assignSection(to: &copy)
            return copy
        }
    }
}

/// 门诊零散记录导入（拍照 OCR / 手输文字）
/// @author jiali.qiu
enum ReportClinicNoteImporter {

    enum ClinicError: LocalizedError {
        case empty
        case noContent

        var errorDescription: String? {
            switch self {
            case .empty: return "请输入或拍摄门诊结论内容"
            case .noContent: return "未能识别指标或结论。请补充化验数值（如「LDL 3.52 mmol/L」）或诊断语句，也可分行粘贴。"
            }
        }
    }

    /// 本地智能解析 + 可选 DeepSeek 补强
    static func importFromText(
        _ text: String,
        sourceType: String = "clinic_note",
        onProgress: ReportImportProgressHandler? = nil
    ) async throws -> ReportImporter.ImportDraft {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ClinicError.empty }

        await ReportImportProgressReporter.emit(onProgress, 0.15, "正在本地解析…")
        var extraction = ReportClinicNoteParser.parse(trimmed)
        var usedAI = false

        if shouldEnrichWithAI(local: extraction, raw: trimmed) {
            await ReportImportProgressReporter.emit(onProgress, 0.42, "正在 DeepSeek 结构化…")
            let sections = ReportAIService.TextSections(
                summary: "",
                labTables: trimmed,
                imaging: trimmed,
                fullText: trimmed
            )
            if let ai = try? await ReportAIService.extractStructuredReport(from: sections), !ai.isEmpty {
                extraction = mergeExtractions(local: extraction, ai: ai)
                usedAI = true
            }
        }

        guard !extraction.isEmpty else { throw ClinicError.noContent }

        await ReportImportProgressReporter.emit(onProgress, 0.62, "正在整理指标…")
        let draft = ReportImporter.ImportDraft(
            fileName: ReportDisplayFormatter.preferredFileName(
                examDate: extraction.examDate,
                original: "门诊记录"
            ),
            sourceType: sourceType,
            rawText: ReportPasteParser.compactStorageText(for: trimmed),
            metrics: categorizedMetrics(extraction.metrics),
            findings: extraction.findings,
            recommendations: extraction.recommendations,
            examDate: extraction.examDate,
            assessmentSummary: extraction.assessmentSummary,
            usedAIAssist: usedAI,
            sanitizedPreview: ReportAIService.sanitizeForCloud(trimmed)
        )
        let aligned = HealthRecordAligner.align(draft: draft)
        await ReportImportProgressReporter.emit(onProgress, 0.78, "正在 AI 标注严重度…")
        let ranked = await ReportAIService.enrichDraftRanking(aligned)
        await ReportImportProgressReporter.emit(onProgress, 1.0, "解析完成，进入校对…")
        return ranked
    }

    static func alignOCRDraft(_ draft: ReportImporter.ImportDraft) -> ReportImporter.ImportDraft {
        var copy = draft
        if copy.sourceType == "screenshot" {
            copy.sourceType = "ocr_clinic"
        }
        return HealthRecordAligner.align(draft: copy)
    }

    /// 本地解析覆盖不足时，用 DeepSeek 结构化补强（需用户在设置中开启）
    private static func shouldEnrichWithAI(
        local: ReportAIService.StructuredExtraction,
        raw: String
    ) -> Bool {
        guard APIKeyManager.isReportAIAssistEnabled, APIKeyManager.isDeepSeekConfigured else {
            return false
        }
        let lines = raw.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard lines.count >= 4 else { return false }

        let parsedItems = local.metrics.count + local.findings.count
        if parsedItems == 0 { return true }
        if lines.count >= 8, parsedItems * 3 < lines.count { return true }
        return false
    }

    private static func mergeExtractions(
        local: ReportAIService.StructuredExtraction,
        ai: ReportAIService.StructuredExtraction
    ) -> ReportAIService.StructuredExtraction {
        var metrics = local.metrics
        var findings = local.findings
        var recommendations = local.recommendations
        var metricKeys = Set(metrics.map { MetricNameCanonicalizer.canonicalKey(for: $0.name) })
        var findingKeys = Set(findings.map { HealthRecordAligner.findingKey(for: $0) })

        for item in ai.metrics {
            let key = MetricNameCanonicalizer.canonicalKey(for: item.name)
            guard !metricKeys.contains(key) else { continue }
            metricKeys.insert(key)
            metrics.append(item)
        }

        for item in ai.findings where !ReportMetricNormalizer.isJunkClinicFinding(item) {
            let key = HealthRecordAligner.findingKey(for: item)
            guard !findingKeys.contains(key) else { continue }
            findingKeys.insert(key)
            findings.append(item)
        }

        for rec in ai.recommendations where !recommendations.contains(rec) {
            recommendations.append(rec)
        }

        return ReportAIService.StructuredExtraction(
            metrics: ReportMetricNormalizer.filterMetrics(metrics),
            findings: ReportMetricNormalizer.dedupeFindings(findings),
            recommendations: recommendations,
            examDate: local.examDate ?? ai.examDate
        )
    }

    private static func categorizedMetrics(_ metrics: [ReportImporter.DraftMetric]) -> [ReportImporter.DraftMetric] {
        metrics.map { item in
            var copy = item
            ReportMetricCategory.assignSection(to: &copy)
            return copy
        }
    }
}
