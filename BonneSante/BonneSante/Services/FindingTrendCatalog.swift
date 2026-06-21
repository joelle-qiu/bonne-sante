import Foundation

/// 检查结论趋势面板与通俗说明
/// @author jiali.qiu
enum FindingTrendCatalog {

    struct PanelMeta {
        let id: String
        let title: String
        let subtitle: String
        let relatedSystems: [String]
        let keyPrefixes: [String]
    }

    struct FindingMeta {
        let plainTitle: String
        let findingType: String
        let relatedTo: String
    }

    static let panels: [PanelMeta] = [
        PanelMeta(
            id: "imaging",
            title: "影像检查",
            subtitle: "CT/MRI 结节、血管瘤等需长期随访的结论",
            relatedSystems: ["胸外科", "肝胆外科", "影像"],
            keyPrefixes: ["imaging."]
        ),
        PanelMeta(
            id: "gynecology",
            title: "妇科",
            subtitle: "子宫、宫颈等妇科相关结论",
            relatedSystems: ["妇科", "生殖"],
            keyPrefixes: ["gyn."]
        ),
        PanelMeta(
            id: "physical",
            title: "体格检查",
            subtitle: "触诊、视诊等物理检查结论",
            relatedSystems: ["外科", "体检"],
            keyPrefixes: ["physical."]
        ),
        PanelMeta(
            id: "functional",
            title: "功能检查",
            subtitle: "心电图等功能性检查结论",
            relatedSystems: ["心血管"],
            keyPrefixes: ["exam."]
        )
    ]

    static func inferPanelId(forCanonicalKey key: String) -> String? {
        for panel in panels {
            if panel.keyPrefixes.contains(where: { key.hasPrefix($0) }) {
                return panel.id
            }
        }
        if key.hasPrefix("finding.") { return "imaging" }
        return nil
    }

    static func classifyStatus(
        points: [HealthFindingTrendEngine.DataPoint],
        canonicalKey: String,
        metricTrend: MetricTrend
    ) -> MetricTrendCatalog.HealthStatus {
        let sorted = lesionTrendPoints(from: points, canonicalKey: canonicalKey)
        guard sorted.count >= 2 else { return .unclear }
        let first = sorted.first!
        let last = sorted.last!

        if FindingNameCanonicalizer.isChronicLesionSeriesKey(canonicalKey) {
            if first.isAbnormal && last.isAbnormal {
                if isImproving(first: first, last: last, trend: metricTrend, canonicalKey: canonicalKey) {
                    return .improvingAbnormal
                }
                if isStableLesion(first: first, last: last, trend: metricTrend) {
                    return .ongoing
                }
                return .ongoing
            }
            if first.isAbnormal && !last.isAbnormal {
                // 慢性病灶序列不因末次阴性扫读判「已好转」
                return .ongoing
            }
            if !first.isAbnormal && last.isAbnormal { return .newConcern }
            return .ongoing
        }

        if first.isAbnormal && !last.isAbnormal { return .recovered }
        if !first.isAbnormal && last.isAbnormal { return .newConcern }
        if !first.isAbnormal && !last.isAbnormal { return .stableGood }

        if first.isAbnormal && last.isAbnormal {
            if isImproving(first: first, last: last, trend: metricTrend, canonicalKey: canonicalKey) {
                return .improvingAbnormal
            }
            return .ongoing
        }
        return .unclear
    }

    /// 慢性病灶序列只保留含病理/尺寸的记录参与对比
    static func lesionTrendPoints(
        from points: [HealthFindingTrendEngine.DataPoint],
        canonicalKey: String
    ) -> [HealthFindingTrendEngine.DataPoint] {
        let sorted = points.sorted { $0.date < $1.date }
        guard FindingNameCanonicalizer.isChronicLesionSeriesKey(canonicalKey) else {
            return sorted
        }
        let filtered = sorted.filter { isPathologicalLesionPoint($0) }
        // 过滤后即使只剩 1 条也不回退到含「未见异常」的完整序列
        return filtered.isEmpty ? sorted : filtered
    }

    /// 慢性病灶趋势点：须在本条记录的描述/数值中含病理或尺寸（不含 assessmentNote 污染）
    static func isPathologicalLesionPoint(_ point: HealthFindingTrendEngine.DataPoint) -> Bool {
        let primary = point.detailText + point.valueText
        let size = point.sizeMillimeters ?? (point.value > 1 ? point.value : nil)
        return hasLesionEvidence(
            in: primary,
            sizeMillimeters: size,
            isAbnormal: point.isAbnormal
        )
    }

    /// 判断主文案是否描述真实病灶（排除仅 assessmentNote / 主检建议 沾词）
    static func hasLesionEvidence(in primaryText: String, sizeMillimeters: Double?, isAbnormal: Bool) -> Bool {
        let blob = RiskAnalyzer.normalize(primaryText)
        let pathologyKeywords = [
            "结节", "磨玻璃", "ggo", "血管瘤", "fnh", "占位", "低回声", "高信号",
            "异常信号", "趋势锚点", "微小结", "磨玻璃结节"
        ]
        let hasPrimaryPathology = pathologyKeywords.contains { blob.contains($0) }
        let hasSize = (sizeMillimeters ?? 0) > 0

        if blob.contains("超声") || blob.contains("b超") {
            if blob.contains("未见") || blob.contains("无占位") || blob.contains("无殊") {
                if !hasPrimaryPathology, !hasSize { return false }
            }
        }
        if blob.contains("未见明显异常") || blob.contains("未见异常") {
            if !hasPrimaryPathology, !hasSize { return false }
        }
        if hasPrimaryPathology || hasSize { return true }
        return isAbnormal && !blob.contains("未见")
    }

    static func findingMeta(forCanonicalKey key: String, fallbackName: String) -> FindingMeta {
        switch key {
        case "gyn.uterus_fibroid":
            return FindingMeta(
                plainTitle: "子宫肌瘤",
                findingType: "妇科影像",
                relatedTo: "良性肌瘤，需关注大小变化与症状"
            )
        case "gyn.cervix_nabothian":
            return FindingMeta(
                plainTitle: "宫颈纳氏囊肿",
                findingType: "妇科",
                relatedTo: "常见良性改变，通常定期复查即可"
            )
        case "gyn.cervix_erosion":
            return FindingMeta(
                plainTitle: "宫颈糜烂样改变",
                findingType: "妇科",
                relatedTo: "建议结合 TCT、HPV 等进一步评估"
            )
        case "imaging.liver", "imaging.liver_lesion":
            return FindingMeta(
                plainTitle: "肝血管瘤/FNH",
                findingType: "腹部影像",
                relatedTo: "需长期肝胆外科或影像随访，关注病灶大小与强化特征变化"
            )
        case "imaging.lung_nodule":
            return FindingMeta(
                plainTitle: "肺部结节",
                findingType: "胸部 CT",
                relatedTo: "磨玻璃/微小结节需按医嘱长期 CT 随访（通常 3–12 月）"
            )
        case "imaging.lung":
            return FindingMeta(
                plainTitle: "肺部",
                findingType: "胸部影像",
                relatedTo: "肺结节需按医嘱定期 CT 随访"
            )
        case "imaging.thyroid":
            return FindingMeta(
                plainTitle: "甲状腺",
                findingType: "颈部影像",
                relatedTo: "建议结合甲状腺功能化验综合判断"
            )
        case "imaging.breast_hyperplasia", "imaging.breast":
            return FindingMeta(
                plainTitle: "乳腺",
                findingType: "乳腺检查",
                relatedTo: "与激素波动相关，建议定期自查与随访"
            )
        case "imaging.cervical_spine":
            return FindingMeta(
                plainTitle: "颈椎曲度",
                findingType: "骨骼影像",
                relatedTo: "与长期低头、姿势相关，有症状需专科"
            )
        case "exam.ecg":
            return FindingMeta(
                plainTitle: "心电图",
                findingType: "功能检查",
                relatedTo: "多数窦性心律不齐为良性，以专科意见为准"
            )
        default:
            return FindingMeta(
                plainTitle: fallbackName,
                findingType: "检查结论",
                relatedTo: "请结合体检报告与医生建议理解"
            )
        }
    }

    private static func isImproving(
        first: HealthFindingTrendEngine.DataPoint,
        last: HealthFindingTrendEngine.DataPoint,
        trend: MetricTrend,
        canonicalKey: String
    ) -> Bool {
        if let firstSize = first.sizeMillimeters, let lastSize = last.sizeMillimeters, firstSize > 0 {
            let delta = lastSize - firstSize
            if FindingNameCanonicalizer.isLowerBetter(canonicalKey: canonicalKey) {
                return delta < -0.5
            }
            return delta > 0.5
        }
        return trend == .improving
    }

    private static func isStableLesion(
        first: HealthFindingTrendEngine.DataPoint,
        last: HealthFindingTrendEngine.DataPoint,
        trend: MetricTrend
    ) -> Bool {
        if let firstSize = first.sizeMillimeters, let lastSize = last.sizeMillimeters, firstSize > 0 {
            return abs(lastSize - firstSize) < 0.5
        }
        let blob = RiskAnalyzer.normalize(last.detailText + last.valueText + last.assessmentNote)
        if blob.contains("相仿") || blob.contains("稳定") || blob.contains("未见明显变化") {
            return true
        }
        return trend == .stable
    }
}
