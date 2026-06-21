import Foundation

/// 组合型检验指标拆分为可趋势对比的单项（校对页可分组展示，入库按子项存储）
/// @author jiali.qiu
enum ReportMetricExpander {

    /// 批量拆分；已拆分的子项（panelName 非空且 name ≠ panelName）不再重复处理
    static func expand(_ metrics: [ReportImporter.DraftMetric]) -> [ReportImporter.DraftMetric] {
        metrics.flatMap { expandOne($0) }
    }

    /// 将误标为 findings 的检验组合迁回 metrics
    static func promoteLabFindings(
        findings: [ReportImporter.DraftFinding],
        metrics: [ReportImporter.DraftMetric]
    ) -> (findings: [ReportImporter.DraftFinding], metrics: [ReportImporter.DraftMetric]) {
        var keptFindings: [ReportImporter.DraftFinding] = []
        var promoted: [ReportImporter.DraftMetric] = metrics

        for finding in findings {
            guard shouldPromoteFinding(finding) else {
                keptFindings.append(finding)
                continue
            }
            let blob = finding.detail.isEmpty ? finding.title : finding.detail
            promoted.append(ReportImporter.DraftMetric(
                name: finding.title,
                valueText: blob,
                isAbnormal: finding.isAbnormal,
                section: ReportMetricCategory.normalizeIncomingSection(finding.category, metricName: finding.title),
                visitDate: finding.visitDate,
                severityRank: finding.severityRank,
                assessmentNote: finding.assessmentNote
            ))
        }
        return (keptFindings, promoted)
    }

    // MARK: - Private

    private static func shouldPromoteFinding(_ finding: ReportImporter.DraftFinding) -> Bool {
        let category = finding.category.trimmingCharacters(in: .whitespaces)
        if category == "检验" || category == "一般检查" || category == "既往史" { return true }
        let title = finding.title.trimmingCharacters(in: .whitespaces)
        if title.contains("组合") || title.contains("全套") || title.contains("分析") { return true }
        if title.contains("既往史") || title.contains("身高体重") { return true }
        let panels = ["肾功能", "肝功能", "血脂", "尿", "阴道", "肿瘤", "幽门", "血糖", "血沉", "涂片"]
        return panels.contains(where: { title.contains($0) })
    }

    private static func expandOne(_ metric: ReportImporter.DraftMetric) -> [ReportImporter.DraftMetric] {
        if !metric.panelName.isEmpty, metric.name != metric.panelName {
            return [metric]
        }
        guard shouldExpand(metric) else { return [metric] }

        let sourceText = compositeSourceText(for: metric)
        let segments = splitSegments(sourceText)
        guard segments.count >= 2 else { return [metric] }

        let panel = metric.name.trimmingCharacters(in: .whitespaces)
        let panelSection = metric.section.isEmpty
            ? (ReportMetricCategory.sectionForPanel(panel).isEmpty
                ? ReportMetricCategory.inferSection(name: panel, valueText: sourceText)
                : ReportMetricCategory.sectionForPanel(panel))
            : metric.section

        var children: [ReportImporter.DraftMetric] = []
        for segment in segments {
            guard var child = parseSegment(segment, panelSection: panelSection) else { continue }
            child.visitDate = metric.visitDate
            child.panelName = panel
            if child.section.isEmpty || child.section == ReportMetricCategory.fallbackSection {
                child.section = panelSection.isEmpty
                    ? ReportMetricCategory.inferSection(name: child.name, valueText: child.valueText)
                    : panelSection
            }
            if metric.referenceRange.isEmpty == false, child.referenceRange.isEmpty {
                child.referenceRange = metric.referenceRange
            }
            finalizeChild(&child, parent: metric, segment: segment)
            children.append(child)
        }

        guard children.count >= 2 else { return [metric] }
        return dedupeChildren(children)
    }

    private static func shouldExpand(_ metric: ReportImporter.DraftMetric) -> Bool {
        let name = metric.name.trimmingCharacters(in: .whitespaces)
        if name.isEmpty { return false }

        // DeepSeek 已预拆：有 panel 且值为单项，不再本地逗号拆分
        if !metric.panelName.isEmpty {
            if metric.name != metric.panelName { return false }
            let source = compositeSourceText(for: metric)
            if splitSegments(source).count < 2 { return false }
        }

        let compositeTitles = [
            "身高体重血压", "既往史", "血脂全套", "全血细胞分析", "肿瘤标志物",
            "尿液分析组合", "肾功能", "肝功能", "阴道分泌物常规组合", "子宫颈涂片"
        ]
        if compositeTitles.contains(where: { name.contains($0) }) { return true }
        if name.contains("组合") || name.contains("全套") || name.contains("分析") { return true }

        let source = compositeSourceText(for: metric)
        return splitSegments(source).count >= 2
    }

    private static func compositeSourceText(for metric: ReportImporter.DraftMetric) -> String {
        let value = metric.valueText.trimmingCharacters(in: .whitespaces)
        let name = metric.name.trimmingCharacters(in: .whitespaces)
        if value.isEmpty { return name }
        if value == name { return name }
        if value.contains("，") || value.contains(",") { return value }
        if value.contains(name) { return value }
        return value
    }

    private static func splitSegments(_ text: String) -> [String] {
        text.components(separatedBy: CharacterSet(charactersIn: "，,"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.count >= 2 }
    }

    private static func parseSegment(_ segment: String, panelSection: String) -> ReportImporter.DraftMetric? {
        if let parsed = HealthMetricLineParser.parse(segment, panelSection: panelSection) {
            return parsed
        }
        return parseEmbeddedSegment(segment, panelSection: panelSection)
    }

    /// 「白细胞计数6.08」「慢性病史无」等无分隔符片段
    private static func parseEmbeddedSegment(_ segment: String, panelSection: String) -> ReportImporter.DraftMetric? {
        let trimmed = segment.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 3 else { return nil }

        if let parsed = HealthMetricLineParser.parse(trimmed.replacingOccurrences(of: "：", with: " "), panelSection: panelSection) {
            return parsed
        }

        guard let regex = try? NSRegularExpression(
            pattern: #"^([\u4e00-\u9fa5A-Za-z（）()%\-/·]{2,28}?)([\d.]+.*)$"#
        ),
              let match = regex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)),
              let nameRange = Range(match.range(at: 1), in: trimmed),
              let valueRange = Range(match.range(at: 2), in: trimmed) else {
            if trimmed.hasSuffix("无") || trimmed.hasSuffix("正常") || trimmed.hasSuffix("阴性") || trimmed.contains("未查见") {
                for suffix in ["未查见", "正常", "阴性", "无"] {
                    guard trimmed.hasSuffix(suffix) else { continue }
                    let name = String(trimmed.dropLast(suffix.count)).trimmingCharacters(in: .whitespaces)
                    guard name.count >= 2 else { return nil }
                    return ReportImporter.DraftMetric(
                        name: ReportMetricNormalizer.normalizeName(name),
                        valueText: suffix,
                        isAbnormal: false,
                        section: panelSection
                    )
                }
            }
            return nil
        }

        let name = ReportMetricNormalizer.normalizeName(String(trimmed[nameRange]))
        let valuePart = String(trimmed[valueRange]).trimmingCharacters(in: .whitespaces)
        guard ReportMetricNormalizer.isLikelyLabMetricName(name), !valuePart.isEmpty else { return nil }

        let value = Double(valuePart.filter { $0.isNumber || $0 == "." }) ?? 0
        let unit = ReportMetricNormalizer.extractAndFixUnit(from: valuePart, explicitUnit: "")
        return ReportImporter.DraftMetric(
            name: name,
            valueText: valuePart,
            value: value,
            unit: unit,
            isAbnormal: inferAbnormal(from: valuePart),
            section: panelSection
        )
    }

    private static func inferAbnormal(from valuePart: String) -> Bool {
        let trimmed = valuePart.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let normalTokens = ["neg", "normal", "阴性", "正常", "无", "未查见", "0", "0.0", "0.00", "0.0%"]
        if normalTokens.contains(where: { trimmed == $0 || trimmed.hasPrefix($0 + " ") }) { return false }
        if trimmed == "ii" || trimmed == "i" { return false }

        if valuePart.contains("+") && !valuePart.contains("+-") && !trimmed.hasPrefix("0") { return true }
        if trimmed.contains("阳性") && !trimmed.contains("阴性") { return true }
        if valuePart.contains("↑") || valuePart.contains("↓") { return true }
        return false
    }

    private static func finalizeChild(
        _ child: inout ReportImporter.DraftMetric,
        parent: ReportImporter.DraftMetric,
        segment: String
    ) {
        var polished = ReportMetricNormalizer.polish(child, lineHint: segment)
        let explicit = inferAbnormal(from: polished.valueText)
        polished.isAbnormal = ReportMetricNormalizer.inferAbnormal(
            value: polished.value,
            referenceRange: polished.referenceRange,
            lineHint: segment + polished.name + polished.valueText,
            explicitFlag: explicit
        )
        if polished.isAbnormal {
            polished.severityRank = max(polished.severityRank, parent.severityRank)
            if polished.assessmentNote.isEmpty, !parent.assessmentNote.isEmpty {
                polished.assessmentNote = parent.assessmentNote
            }
        } else {
            polished.severityRank = 0
            polished.assessmentNote = ""
        }
        child = polished
    }

    private static func dedupeChildren(_ items: [ReportImporter.DraftMetric]) -> [ReportImporter.DraftMetric] {
        var seen = Set<String>()
        var result: [ReportImporter.DraftMetric] = []
        for item in items {
            let key = MetricNameCanonicalizer.canonicalKey(for: item.name).lowercased()
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            result.append(item)
        }
        return result
    }
}
