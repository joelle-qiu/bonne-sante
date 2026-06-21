import Foundation

/// CT/MRI 长期随访结论（肺磨玻璃结节、肝血管瘤/FNH）定制增强
/// @author jiali.qiu
enum ImagingFollowUpEnricher {

    /// 识别用户常粘贴的影像随访 findings 片段
    static func isImagingFollowUpPaste(_ text: String) -> Bool {
        // 完整体检/多报告 JSON 体积大且含大量 metrics，不走影像片段捷径（避免误解析与内存峰值）
        if text.utf8.count > 12_000 { return false }
        let blob = RiskAnalyzer.normalize(text)
        guard blob.contains("category") else { return false }
        if blob.contains("\"metrics\"") {
            let sectionHints = blob.components(separatedBy: "\"section\"").count - 1
            if sectionHints >= 6 { return false }
        }
        let hasLung = blob.contains("磨玻璃") || (blob.contains("肺") && blob.contains("nodule"))
        let hasLiver = blob.contains("血管瘤") || blob.contains("fnh") || blob.contains("hemangioma")
        return hasLung || hasLiver
    }

    /// 批量增强 findings（粘贴导入 / 对齐入库前调用）
    static func enrichAll(_ findings: [ReportImporter.DraftFinding]) -> [ReportImporter.DraftFinding] {
        findings.map { enrich($0) }
    }

    static func enrich(_ finding: ReportImporter.DraftFinding) -> ReportImporter.DraftFinding {
        var copy = finding
        let blob = RiskAnalyzer.normalize(
            copy.title + copy.detail + copy.conclusion + copy.assessmentNote
        )

        if isLungNoduleFinding(copy, blob: blob) {
            copy = enrichLungNodule(copy, blob: blob)
        } else         if isLiverLesionFinding(copy, blob: blob) {
            copy = enrichLiverLesion(copy, blob: blob)
        } else if isFibroidFinding(copy, blob: blob) {
            copy = enrichFibroid(copy, blob: blob)
        }

        if copy.morphology.isEmpty || copy.organSite.isEmpty {
            let inferred = ClinicalFindingTaxonomy.inferFromText(blob)
            if copy.morphology.isEmpty, inferred.morphology != .other {
                copy.morphology = inferred.morphology.rawValue
            }
            if copy.organSite.isEmpty, inferred.organSite != .other {
                copy.organSite = inferred.organSite.rawValue
            }
        }

        if copy.severityRank < 3, copy.isAbnormal, requiresLongTermFollowUp(copy) {
            copy.severityRank = 3
        }

        return copy
    }

    /// 从增强后的 findings 生成顶层随访摘要
    static func buildAssessmentSummary(from findings: [ReportImporter.DraftFinding]) -> String {
        var parts: [String] = []
        let lung = findings.filter { $0.organSite == "lung" || RiskAnalyzer.normalize($0.title + $0.detail).contains("肺") }
        let liver = findings.filter { $0.organSite == "liver" || RiskAnalyzer.normalize($0.title + $0.detail).contains("肝") }
        if !lung.isEmpty {
            parts.append("肺部结节需长期 CT 随访（仅供参考，请遵医嘱）")
        }
        if !liver.isEmpty {
            parts.append("肝血管瘤/FNH 需影像/肝胆外科长期随访（仅供参考，请遵医嘱）")
        }
        return parts.joined(separator: "；")
    }

    /// 提取主结节最大径（mm），供趋势与入库 size 使用
    static func primarySizeMillimeters(from finding: ReportImporter.DraftFinding) -> Double? {
        if let explicit = finding.primarySizeMm, explicit > 0 {
            return explicit
        }
        let text = finding.detail + finding.conclusion + finding.assessmentNote
        if isLungNoduleFinding(finding, blob: RiskAnalyzer.normalize(text)) {
            return extractPrimaryGGOMillimeters(from: text)
                ?? FindingSizeParser.maxMillimeters(in: text)
        }
        if isLiverLesionFinding(finding, blob: RiskAnalyzer.normalize(text)) {
            return extractHemangiomaPrimaryMillimeters(from: text)
                ?? FindingSizeParser.maxMillimeters(in: text)
        }
        return FindingSizeParser.maxMillimeters(in: text)
    }

    // MARK: - Lung

    private static func isLungNoduleFinding(_ finding: ReportImporter.DraftFinding, blob: String) -> Bool {
        if finding.organSite == "lung" { return true }
        if finding.morphology == "nodule", finding.organSite.isEmpty { return blob.contains("肺") }
        return blob.contains("肺") && (blob.contains("结节") || blob.contains("磨玻璃") || blob.contains("ggo"))
    }

    private static func enrichLungNodule(
        _ finding: ReportImporter.DraftFinding,
        blob: String
    ) -> ReportImporter.DraftFinding {
        var copy = finding
        copy.category = "影像"
        copy.morphology = "nodule"
        copy.organSite = "lung"
        if !copy.morphologyTags.contains("ggo"), blob.contains("磨玻璃") {
            copy.morphologyTags.append("ggo")
        }

        let primaryMM = finding.primarySizeMm
            ?? extractPrimaryGGOMillimeters(from: copy.detail + copy.conclusion)
        let hu = finding.ctValueHu ?? extractCTHu(from: copy.detail)
        let stable = blob.contains("相仿") || blob.contains("稳定") || blob.contains("未见明显变化")

        var summaryParts: [String] = []
        if let primaryMM {
            summaryParts.append(String(format: "主结节 %.1fmm", primaryMM))
        }
        if blob.contains("磨玻璃") { summaryParts.append("磨玻璃") }
        if let hu { summaryParts.append("CT \(hu)Hu") }
        if stable { summaryParts.append("较前相仿") }
        if !summaryParts.isEmpty {
            let prefix = summaryParts.joined(separator: " · ")
            if !copy.assessmentNote.contains(prefix) {
                copy.assessmentNote = copy.assessmentNote.isEmpty
                    ? "\(prefix)；建议 3–6 月 CT 随访"
                    : "\(prefix)；\(copy.assessmentNote)"
            }
        } else if copy.assessmentNote.isEmpty {
            copy.assessmentNote = "建议 3–6 月 CT 随访"
        }

        if primaryMM != nil, !copy.detail.contains("最大径约") {
            copy.detail = "【趋势锚点】最大径约\(String(format: "%.1f", primaryMM!))mm。" + copy.detail
        }

        copy.isAbnormal = true
        copy.severityRank = max(copy.severityRank, stable ? 3 : 3)
        return copy
    }

    /// 优先取磨玻璃结节长径（mm）
    static func extractPrimaryGGOMillimeters(from text: String) -> Double? {
        let normalized = text
            .replacingOccurrences(of: "×", with: "x")
            .replacingOccurrences(of: "＊", with: "x")

        let patterns = [
            #"磨玻璃结节[^。；]{0,40}?长径约?\s*(\d+(?:\.\d+)?)\s*mm"#,
            #"磨玻璃[^。；]{0,30}?(\d+(?:\.\d+)?)\s*mm"#,
            #"长径约?\s*(\d+(?:\.\d+)?)\s*mm"#
        ]
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
               let match = regex.firstMatch(in: normalized, range: NSRange(normalized.startIndex..., in: normalized)),
               match.numberOfRanges > 1,
               let range = Range(match.range(at: 1), in: normalized),
               let value = Double(normalized[range]) {
                return value
            }
        }
        return nil
    }

    private static func extractCTHu(from text: String) -> Int? {
        guard let regex = try? NSRegularExpression(pattern: #"CT值为?\s*(-?\d+)\s*Hu"#, options: .caseInsensitive),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: text),
              let value = Int(text[range]) else {
            return nil
        }
        return value
    }

    // MARK: - Liver

    /// 从「较大灶」语境提取肝血管瘤主径（mm），避免 FNH 小灶干扰趋势
    static func extractHemangiomaPrimaryMillimeters(from text: String) -> Double? {
        let normalized = text
            .replacingOccurrences(of: "×", with: "x")
            .replacingOccurrences(of: "＊", with: "x")

        let contextPatterns = [
            #"较大[^。；]{0,40}?大小约?\s*(\d+(?:\.\d+)?)\s*mm\s*[xX]\s*(\d+(?:\.\d+)?)\s*mm"#,
            #"较大[^。；]{0,40}?大小约?\s*(\d+(?:\.\d+)?)\s*[xX]\s*(\d+(?:\.\d+)?)\s*cm"#,
            #"较大[^。；]{0,40}?大小约?\s*(\d+(?:\.\d+)?)\s*cm"#
        ]
        for pattern in contextPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
               let match = regex.firstMatch(in: normalized, range: NSRange(normalized.startIndex..., in: normalized)) {
                var values: [Double] = []
                for index in 1..<match.numberOfRanges {
                    guard let range = Range(match.range(at: index), in: normalized),
                          let value = Double(normalized[range]) else { continue }
                    values.append(pattern.contains("cm") ? value * 10 : value)
                }
                if let max = values.max() { return max }
            }
        }
        return nil
    }

    private static func isLiverLesionFinding(_ finding: ReportImporter.DraftFinding, blob: String) -> Bool {
        if finding.organSite == "liver" { return true }
        if finding.morphology == "hemangioma" { return true }
        return blob.contains("肝") && (blob.contains("血管瘤") || blob.contains("fnh"))
    }

    private static func enrichLiverLesion(
        _ finding: ReportImporter.DraftFinding,
        blob: String
    ) -> ReportImporter.DraftFinding {
        var copy = finding
        copy.category = "影像"
        copy.morphology = "hemangioma"
        copy.organSite = "liver"
        if blob.contains("fnh"), !copy.morphologyTags.contains("fnh") {
            copy.morphologyTags.append("fnh")
        }

        let maxMM = finding.primarySizeMm
            ?? extractHemangiomaPrimaryMillimeters(from: copy.detail + copy.conclusion)
            ?? FindingSizeParser.maxMillimeters(in: copy.detail + copy.conclusion)
        let fnhMM = finding.secondarySizeMm ?? extractFNHMillimeters(from: copy.detail)

        var summaryParts: [String] = ["肝血管瘤"]
        if blob.contains("fnh") { summaryParts.append("FNH") }
        if let maxMM { summaryParts.append(String(format: "较大灶 %.0fmm", maxMM)) }
        if let fnhMM { summaryParts.append(String(format: "FNH %.0fmm", fnhMM)) }

        let prefix = summaryParts.joined(separator: " · ")
        if !copy.assessmentNote.contains("肝血管瘤") {
            copy.assessmentNote = copy.assessmentNote.isEmpty
                ? "\(prefix)；建议肝胆外科/影像长期随访"
                : "\(prefix)；\(copy.assessmentNote)"
        }

        if maxMM != nil, !copy.detail.contains("最大径约") {
            copy.detail = "【趋势锚点】最大径约\(String(format: "%.0f", maxMM! / 10))cm（\(String(format: "%.0f", maxMM!))mm）。"
                + copy.detail
        }

        copy.isAbnormal = true
        copy.severityRank = max(copy.severityRank, 3)
        return copy
    }

    private static func extractFNHMillimeters(from text: String) -> Double? {
        guard let regex = try? NSRegularExpression(
            pattern: #"FNH[^。；]{0,20}?(\d+(?:\.\d+)?)\s*[xX×]\s*(\d+(?:\.\d+)?)\s*cm"#,
            options: .caseInsensitive
        ),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else {
            return nil
        }
        var values: [Double] = []
        for index in 1..<match.numberOfRanges {
            guard let range = Range(match.range(at: index), in: text),
                  let value = Double(text[range]) else { continue }
            values.append(value * 10)
        }
        return values.max()
    }

    private static func requiresLongTermFollowUp(_ finding: ReportImporter.DraftFinding) -> Bool {
        let blob = RiskAnalyzer.normalize(
            finding.title + finding.detail + finding.conclusion + finding.morphology + finding.organSite
        )
        return blob.contains("磨玻璃") || blob.contains("结节") || blob.contains("血管瘤")
            || blob.contains("fnh") || blob.contains("肌瘤")
            || finding.morphology == "nodule" || finding.morphology == "hemangioma"
            || finding.morphology == "fibroid"
    }

    // MARK: - Uterine fibroid

    private static func isFibroidFinding(_ finding: ReportImporter.DraftFinding, blob: String) -> Bool {
        if finding.organSite == "uterus", finding.morphology == "fibroid" { return true }
        return blob.contains("肌瘤") || blob.contains("fibroid")
    }

    private static func enrichFibroid(
        _ finding: ReportImporter.DraftFinding,
        blob: String
    ) -> ReportImporter.DraftFinding {
        var copy = finding
        copy.category = copy.category.isEmpty ? "妇科" : copy.category
        copy.morphology = "fibroid"
        copy.organSite = "uterus"
        let maxMM = FindingSizeParser.maxMillimeters(in: copy.detail + copy.conclusion)
        if let maxMM, !copy.detail.contains("最大径约") {
            copy.detail = "【趋势锚点】最大径约\(String(format: "%.0f", maxMM))mm。" + copy.detail
        }
        if let maxMM, copy.assessmentNote.isEmpty {
            copy.assessmentNote = "子宫肌瘤约 \(String(format: "%.0f", maxMM)) mm，建议妇科定期复查"
        }
        copy.isAbnormal = true
        copy.severityRank = max(copy.severityRank, 3)
        return copy
    }
}
