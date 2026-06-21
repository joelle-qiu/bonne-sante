import Foundation

/// 跨报告检查结论（findings）名称归一
/// @author jiali.qiu
enum FindingNameCanonicalizer {

    struct Entry {
        let canonicalKey: String
        let displayName: String
        let sizeMillimeters: Double?
        let isAbnormal: Bool
        let detailText: String
    }

    /// 从单条「异常发现」展开为可对比条目（一条结论可映射多个器官）
    static func entries(from metric: HealthMetric) -> [Entry] {
        guard isTrendFindingMetric(metric) else { return [] }

        let title = metric.name.trimmingCharacters(in: .whitespaces)
        let detail = detailFrom(metric)
        let blob = RiskAnalyzer.normalize(
            title + detail + metric.valueText + metric.assessmentNote
                + metric.morphologyTag + metric.organSiteTag
        )

        if let key = taxonomyCanonicalKey(morphologyTag: metric.morphologyTag, organSiteTag: metric.organSiteTag, blob: blob) {
            let parsed = FindingSizeParser.maxMillimeters(in: title + " " + detail + " " + metric.valueText)
            let size = parsed ?? (metric.value > 0 ? metric.value : nil)
            return [Entry(
                canonicalKey: key,
                displayName: plainTitle(for: key, fallback: title),
                sizeMillimeters: size,
                isAbnormal: metric.isAbnormal,
                detailText: detail.isEmpty ? title : detail
            )]
        }

        if isOrganNormalScan(blob, isAbnormal: metric.isAbnormal) {
            return organNormalEntries(title: title, detail: detail, blob: blob)
        }

        guard let key = canonicalKey(from: blob, title: title) else { return [] }
        let size = FindingSizeParser.maxMillimeters(in: title + " " + detail + " " + metric.valueText)
        return [Entry(
            canonicalKey: key,
            displayName: plainTitle(for: key, fallback: title),
            sizeMillimeters: size,
            isAbnormal: metric.isAbnormal,
            detailText: detail.isEmpty ? title : detail
        )]
    }

    static func canonicalKey(for metric: HealthMetric) -> String? {
        entries(from: metric).first?.canonicalKey
    }

    /// 趋势序列归一 key（合并 imaging.lung / finding.lung_nodule 等别名）
    static func trendSeriesKey(for metric: HealthMetric) -> String? {
        guard let entry = entries(from: metric).first else { return nil }
        return normalizedTrendKey(entry.canonicalKey, metric: metric)
    }

    /// 有尺寸时，数值越小通常越好
    static func isLowerBetter(canonicalKey: String) -> Bool {
        switch canonicalKey {
        case "imaging.liver_lesion", "imaging.liver":
            return true
        default:
            return true
        }
    }

    /// 与 HealthProfileEngine 一致：异常发现 + 影像/心电图章节 + AI 标签
    static func isTrendFindingMetric(_ metric: HealthMetric) -> Bool {
        if metric.category == "异常发现" { return true }
        if metric.reportSection == "影像检查" || metric.reportSection == "心电图" { return true }
        return !metric.morphologyTag.isEmpty || !metric.organSiteTag.isEmpty
    }

    /// 需长期影像随访、不应因「未见异常」判为已好转的序列
    static func isChronicLesionSeriesKey(_ key: String) -> Bool {
        key == "imaging.lung_nodule" || key == "imaging.liver_lesion"
    }

    /// 慢性病灶序列：排除正常扫读/阴性描述，只保留真实病灶记录
    static func isLesionFollowUpDataPoint(
        seriesKey: String,
        entry: Entry,
        metric: HealthMetric
    ) -> Bool {
        guard isChronicLesionSeriesKey(seriesKey) else { return true }

        let primary = metric.name + metric.valueText + entry.detailText + metric.assessmentNote
        let size = entry.sizeMillimeters ?? (metric.value > 0 ? metric.value : nil)
        let blob = RiskAnalyzer.normalize(primary)
        if blob.contains("未见明显异常") || blob.contains("目前未见") { return false }
        guard (size ?? 0) > 0 else { return false }
        return FindingTrendCatalog.hasLesionEvidence(
            in: primary,
            sizeMillimeters: size,
            isAbnormal: metric.isAbnormal || entry.isAbnormal
        )
    }

    // MARK: - Private

    private static func detailFrom(_ metric: HealthMetric) -> String {
        let text = metric.valueText.trimmingCharacters(in: .whitespaces)
        let name = metric.name.trimmingCharacters(in: .whitespaces)
        if text.hasPrefix(name) {
            return String(text.dropFirst(name.count)).trimmingCharacters(in: .whitespaces)
        }
        if text == name { return "" }
        return text
    }

    private static func isOrganNormalScan(_ blob: String, isAbnormal: Bool) -> Bool {
        if blob.contains("结节") || blob.contains("血管瘤") || blob.contains("占位") || blob.contains("磨玻璃") {
            return false
        }
        return !isAbnormal && (blob.contains("未见明显异常") || blob.contains("未见异常") || blob.contains("目前未见"))
    }

    private static func organNormalEntries(title: String, detail: String, blob: String) -> [Entry] {
        let organs: [(keyword: String, key: String, label: String)] = [
            ("肝脏", "imaging.liver", "肝脏"),
            ("胆囊", "imaging.gallbladder", "胆囊"),
            ("脾脏", "imaging.spleen", "脾脏"),
            ("肾脏", "imaging.kidney", "肾脏"),
            ("胰腺", "imaging.pancreas", "胰腺"),
            ("甲状腺", "imaging.thyroid", "甲状腺"),
            ("心肺", "imaging.heart_lung", "心肺"),
            ("胸部", "imaging.lung", "肺部"),
            ("肺部", "imaging.lung", "肺部"),
            ("肺", "imaging.lung", "肺部"),
            ("乳房", "imaging.breast", "乳房"),
            ("乳腺", "imaging.breast", "乳腺")
        ]
        var result: [Entry] = []
        for organ in organs where blob.contains(organ.keyword) {
            result.append(Entry(
                canonicalKey: organ.key,
                displayName: organ.label,
                sizeMillimeters: nil,
                isAbnormal: false,
                detailText: detail.isEmpty ? title : detail
            ))
        }
        return result
    }

    private static func canonicalKey(from blob: String, title: String) -> String? {
        if blob.contains("子宫肌瘤") || blob.contains("子宫平滑肌") { return "gyn.uterus_fibroid" }
        if blob.contains("纳氏") || blob.contains("腺囊肿") { return "gyn.cervix_nabothian" }
        if blob.contains("宫颈糜烂") { return "gyn.cervix_erosion" }

        if blob.contains("肺") && (blob.contains("结节") || blob.contains("磨玻璃") || blob.contains("ggo")) {
            return blob.contains("磨玻璃") ? "imaging.lung_nodule" : "imaging.lung"
        }
        if blob.contains("胸") && blob.contains("ct") && blob.contains("结节") { return "imaging.lung" }
        if blob.contains("肝") && (blob.contains("低回声") || blob.contains("血管瘤") || blob.contains("占位") || blob.contains("fnh") || blob.contains("高信号")) {
            return "imaging.liver_lesion"
        }
        if blob.contains("甲状腺") && (blob.contains("欠均匀") || blob.contains("结节") || blob.contains("增粗")) {
            return "imaging.thyroid"
        }
        if blob.contains("甲状腺") && blob.contains("未见") { return "imaging.thyroid" }

        if blob.contains("乳腺") || blob.contains("乳房") {
            if blob.contains("增生") || blob.contains("小叶") || blob.contains("增厚") {
                return "imaging.breast_hyperplasia"
            }
        }

        if blob.contains("颈椎") && (blob.contains("曲度变直") || blob.contains("生理曲度")) {
            return "imaging.cervical_spine"
        }

        if blob.contains("心电图") || blob.contains("窦性") || blob.contains("心律") {
            return "exam.ecg"
        }

        if blob.contains("肛指") { return "exam.rectal" }

        let normalizedTitle = RiskAnalyzer.normalize(title)
        if !normalizedTitle.isEmpty { return "finding.\(normalizedTitle)" }
        return nil
    }

    /// 合并趋势别名，避免同项被拆成多条单次记录
    static func normalizedTrendKey(_ rawKey: String, metric: HealthMetric) -> String {
        let blob = RiskAnalyzer.normalize(
            metric.name + metric.valueText + metric.assessmentNote
                + metric.morphologyTag + metric.organSiteTag
        )
        let morph = ClinicalFindingTaxonomy.normalizeMorphology(metric.morphologyTag)
        let organ = ClinicalFindingTaxonomy.normalizeOrganSite(metric.organSiteTag)

        if organ == .lung || rawKey.contains("lung") || blob.contains("肺") {
            if morph == .nodule || morph == .tumor
                || blob.contains("结节") || blob.contains("磨玻璃") || blob.contains("ggo") {
                return "imaging.lung_nodule"
            }
        }
        if organ == .liver || rawKey.contains("liver") || blob.contains("肝") {
            if morph == .hemangioma || morph == .nodule || morph == .tumor
                || blob.contains("血管瘤") || blob.contains("fnh") || blob.contains("低回声") || blob.contains("占位") {
                return "imaging.liver_lesion"
            }
        }
        if rawKey == "finding.lung_nodule" { return "imaging.lung_nodule" }
        if rawKey == "finding.liver_hemangioma" || rawKey == "finding.liver_nodule" {
            return "imaging.liver_lesion"
        }
        return rawKey
    }

    /// 优先使用 DeepSeek 标注的 morphology / organSite
    private static func taxonomyCanonicalKey(morphologyTag: String, organSiteTag: String, blob: String) -> String? {
        var morph = ClinicalFindingTaxonomy.normalizeMorphology(morphologyTag)
        var organ = ClinicalFindingTaxonomy.normalizeOrganSite(organSiteTag)
        if morph == .other, organ == .other {
            let inferred = ClinicalFindingTaxonomy.inferFromText(blob)
            guard !inferred.isEmpty else { return nil }
            morph = inferred.morphology
            organ = inferred.organSite
        }

        switch (organ, morph) {
        case (.lung, .nodule), (.lung, .tumor):
            return "imaging.lung_nodule"
        case (.liver, .hemangioma), (.liver, .nodule), (.liver, .tumor):
            return "imaging.liver_lesion"
        case (.cervix, .cyst):
            return "gyn.cervix_nabothian"
        case (.uterus, .fibroid):
            return "gyn.uterus_fibroid"
        case (.breast, .hyperplasia):
            return "imaging.breast_hyperplasia"
        case (.spine, .structural):
            return "imaging.cervical_spine"
        case (.thyroid, .echoAbnormal), (.thyroid, .nodule):
            return "imaging.thyroid"
        case (.heart, .arrhythmia):
            return "exam.ecg"
        case (.dental, .stone):
            return "finding.dental_stone"
        default:
            break
        }

        if organ == .liver, morph.isClinicallySignificant { return "imaging.liver_lesion" }
        if organ != .other, morph != .other { return "finding.\(organ.rawValue)_\(morph.rawValue)" }
        if organ != .other { return "finding.\(organ.rawValue)" }
        return nil
    }

    static func plainTitle(for key: String, fallback: String) -> String {
        switch key {
        case "gyn.uterus_fibroid": return "子宫肌瘤"
        case "gyn.cervix_nabothian": return "宫颈纳氏囊肿"
        case "gyn.cervix_erosion": return "宫颈糜烂样改变"
        case "imaging.liver_lesion": return "肝血管瘤/FNH"
        case "imaging.liver": return "肝脏"
        case "imaging.lung_nodule": return "肺部结节（磨玻璃）"
        case "imaging.lung": return "肺部"
        case "imaging.gallbladder": return "胆囊"
        case "imaging.spleen": return "脾脏"
        case "imaging.kidney": return "肾脏"
        case "imaging.pancreas": return "胰腺"
        case "imaging.thyroid": return "甲状腺"
        case "imaging.heart_lung": return "心肺"
        case "imaging.breast": return "乳腺"
        case "imaging.breast_hyperplasia": return "乳腺小叶增生"
        case "imaging.cervical_spine": return "颈椎曲度"
        case "exam.ecg": return "心电图"
        case "exam.rectal": return "肛门指检"
        case "finding.dental_stone": return "牙结石"
        default:
            return fallback
        }
    }
}

/// 从描述文本解析病灶尺寸（取最大径，单位 mm）
/// @author jiali.qiu
enum FindingSizeParser {

    static func maxMillimeters(in text: String) -> Double? {
        let normalized = text
            .replacingOccurrences(of: "×", with: "x")
            .replacingOccurrences(of: "＊", with: "x")
            .replacingOccurrences(of: "*", with: "x")

        var values: [Double] = []

        if let regex = try? NSRegularExpression(pattern: #"【趋势锚点】最大径约(\d+(?:\.\d+)?)\s*mm"#) {
            let range = NSRange(normalized.startIndex..., in: normalized)
            if let match = regex.firstMatch(in: normalized, range: range),
               match.numberOfRanges > 1,
               let swiftRange = Range(match.range(at: 1), in: normalized),
               let value = Double(normalized[swiftRange]) {
                return value
            }
        }

        if let regex = try? NSRegularExpression(pattern: #"(\d+(?:\.\d+)?)\s*mm\s*[xX]\s*(\d+(?:\.\d+)?)\s*mm"#) {
            let range = NSRange(normalized.startIndex..., in: normalized)
            regex.enumerateMatches(in: normalized, range: range) { match, _, _ in
                guard let match else { return }
                for index in 1..<match.numberOfRanges {
                    let nsRange = match.range(at: index)
                    guard nsRange.location != NSNotFound, let swiftRange = Range(nsRange, in: normalized) else { continue }
                    if let value = Double(normalized[swiftRange]) { values.append(value) }
                }
            }
        }

        if let regex = try? NSRegularExpression(pattern: #"(\d+(?:\.\d+)?)\s*[xX]\s*(\d+(?:\.\d+)?)(?:\s*[xX]\s*(\d+(?:\.\d+)?))?\s*mm"#) {
            let range = NSRange(normalized.startIndex..., in: normalized)
            regex.enumerateMatches(in: normalized, range: range) { match, _, _ in
                guard let match else { return }
                for index in 1..<match.numberOfRanges {
                    let nsRange = match.range(at: index)
                    guard nsRange.location != NSNotFound, let swiftRange = Range(nsRange, in: normalized) else { continue }
                    if let value = Double(normalized[swiftRange]) { values.append(value) }
                }
            }
        }

        if let regex = try? NSRegularExpression(pattern: #"(\d+(?:\.\d+)?)\s*-\s*(\d+(?:\.\d+)?)\s*mm"#) {
            let range = NSRange(normalized.startIndex..., in: normalized)
            regex.enumerateMatches(in: normalized, range: range) { match, _, _ in
                guard let match, match.numberOfRanges > 2,
                      let r1 = Range(match.range(at: 1), in: normalized),
                      let r2 = Range(match.range(at: 2), in: normalized),
                      let v1 = Double(normalized[r1]),
                      let v2 = Double(normalized[r2]) else { return }
                values.append(max(v1, v2))
            }
        }

        if let regex = try? NSRegularExpression(pattern: #"大小约?\s*(\d+(?:\.\d+)?)\s*mm"#) {
            let range = NSRange(normalized.startIndex..., in: normalized)
            regex.enumerateMatches(in: normalized, range: range) { match, _, _ in
                guard let match, match.numberOfRanges > 1,
                      let swiftRange = Range(match.range(at: 1), in: normalized),
                      let value = Double(normalized[swiftRange]) else { return }
                values.append(value)
            }
        }

        if let regex = try? NSRegularExpression(pattern: #"长径约?\s*(\d+(?:\.\d+)?)\s*mm"#) {
            let range = NSRange(normalized.startIndex..., in: normalized)
            regex.enumerateMatches(in: normalized, range: range) { match, _, _ in
                guard let match, match.numberOfRanges > 1,
                      let swiftRange = Range(match.range(at: 1), in: normalized),
                      let value = Double(normalized[swiftRange]) else { return }
                values.append(value)
            }
        }

        if let regex = try? NSRegularExpression(pattern: #"约?\s*(\d+(?:\.\d+)?)\s*mm"#) {
            let range = NSRange(normalized.startIndex..., in: normalized)
            regex.enumerateMatches(in: normalized, range: range) { match, _, _ in
                guard let match, match.numberOfRanges > 1,
                      let swiftRange = Range(match.range(at: 1), in: normalized),
                      let value = Double(normalized[swiftRange]) else { return }
                values.append(value)
            }
        }

        if let regex = try? NSRegularExpression(pattern: #"(\d+(?:\.\d+)?)\s*[xX]\s*(\d+(?:\.\d+)?)(?:\s*[xX]\s*(\d+(?:\.\d+)?))?\s*cm"#) {
            let range = NSRange(normalized.startIndex..., in: normalized)
            regex.enumerateMatches(in: normalized, range: range) { match, _, _ in
                guard let match else { return }
                for index in 1..<match.numberOfRanges {
                    let nsRange = match.range(at: index)
                    guard nsRange.location != NSNotFound, let swiftRange = Range(nsRange, in: normalized) else { continue }
                    if let value = Double(normalized[swiftRange]) { values.append(value * 10) }
                }
            }
        }

        if let regex = try? NSRegularExpression(pattern: #"约?\s*(\d+(?:\.\d+)?)\s*cm"#) {
            let range = NSRange(normalized.startIndex..., in: normalized)
            regex.enumerateMatches(in: normalized, range: range) { match, _, _ in
                guard let match, match.numberOfRanges > 1,
                      let swiftRange = Range(match.range(at: 1), in: normalized),
                      let value = Double(normalized[swiftRange]) else { return }
                values.append(value * 10)
            }
        }

        return values.max()
    }
}
