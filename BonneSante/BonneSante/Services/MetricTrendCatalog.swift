import Foundation

/// 指标通俗说明与趋势健康状态（非医学诊断）
/// @author jiali.qiu
enum MetricTrendCatalog {

    enum HealthStatus: String, CaseIterable {
        case newConcern = "新出现"
        case ongoing = "仍需关注"
        case improvingAbnormal = "好转中"
        case recovered = "已好转"
        case stableGood = "保持正常"
        case singleRecord = "待复查对比"
        case unclear = "观察中"

        var sortPriority: Int {
            switch self {
            case .newConcern: return 5
            case .ongoing: return 4
            case .improvingAbnormal: return 3
            case .recovered: return 2
            case .singleRecord: return 2
            case .unclear: return 1
            case .stableGood: return 0
            }
        }

        var summaryHint: String {
            switch self {
            case .recovered: return "之前有问题，最近已恢复正常"
            case .newConcern: return "之前正常，最近出现异常"
            case .ongoing: return "两次体检均异常，建议随访"
            case .improvingAbnormal: return "仍异常，但较上次朝正常方向改善"
            case .stableGood: return "两次体检均在参考范围内"
            case .singleRecord: return "仅一次体检有记录，待下次同项对比"
            case .unclear: return "数据不足，建议结合报告判断"
            }
        }
    }

    /// 单次记录说明（跨院体检仅测一次时使用）
    static func singleRecordNote(date: Date, valueText: String, isAbnormal: Bool) -> String {
        let formatted = ReportDisplayFormatter.examDateLabel(date)
        var parts = ["仅在 \(formatted) 有记录"]
        if !valueText.isEmpty { parts.append(valueText) }
        if isAbnormal { parts.append("当时异常") }
        parts.append("待下次同项复查对比")
        return parts.joined(separator: " · ")
    }

    struct PanelMeta {
        let id: String
        let title: String
        let subtitle: String
        let relatedSystems: [String]
        let keywords: [String]
    }

    struct MetricMeta {
        let plainTitle: String
        let metricType: String
        let relatedTo: String
    }

    static let panels: [PanelMeta] = [
        PanelMeta(
            id: "lipid",
            title: "血脂",
            subtitle: "反映脂质代谢，与心脑血管风险相关",
            relatedSystems: ["心血管", "代谢"],
            keywords: ["胆固醇", "甘油三酯", "脂蛋白", "hdl", "ldl", "lipid."]
        ),
        PanelMeta(
            id: "glucose",
            title: "血糖",
            subtitle: "反映糖代谢，与糖尿病风险相关",
            relatedSystems: ["代谢", "内分泌"],
            keywords: ["血糖", "糖化", "glucose."]
        ),
        PanelMeta(
            id: "liver",
            title: "肝功能",
            subtitle: "反映肝细胞损伤与胆代谢",
            relatedSystems: ["消化", "代谢"],
            keywords: ["转氨酶", "胆红素", "ldh", "liver."]
        ),
        PanelMeta(
            id: "kidney",
            title: "肾功能",
            subtitle: "反映肾脏滤过与排泄能力",
            relatedSystems: ["泌尿", "代谢"],
            keywords: ["尿素", "肌酐", "尿酸", "egfr", "kidney."]
        ),
        PanelMeta(
            id: "blood",
            title: "血常规",
            subtitle: "反映贫血、感染及血液基础状态",
            relatedSystems: ["血液", "免疫"],
            keywords: ["血红蛋白", "白细胞计数", "血小板", "blood."]
        ),
        PanelMeta(
            id: "urine",
            title: "尿常规",
            subtitle: "反映泌尿道与肾脏排泄情况",
            relatedSystems: ["泌尿", "肾脏"],
            keywords: ["尿潜血", "尿隐血", "尿蛋白", "尿白细胞", "urine."]
        ),
        PanelMeta(
            id: "gynecology",
            title: "妇科检验",
            subtitle: "阴道分泌物等妇科相关化验",
            relatedSystems: ["妇科", "生殖"],
            keywords: ["阴道分泌物", "gyn."]
        ),
        PanelMeta(
            id: "coagulation",
            title: "凝血功能",
            subtitle: "反映凝血与纤溶状态",
            relatedSystems: ["血液", "心血管"],
            keywords: ["凝血", "二聚体", "纤维蛋白", "coag."]
        ),
        PanelMeta(
            id: "cardiac",
            title: "心脏标志物",
            subtitle: "反映心肌损伤与心功能",
            relatedSystems: ["心血管"],
            keywords: ["肌钙蛋白", "利钠肽", "肌红蛋白", "cardiac."]
        ),
        PanelMeta(
            id: "thyroid",
            title: "甲状腺功能",
            subtitle: "反映甲状腺激素与自身免疫",
            relatedSystems: ["内分泌"],
            keywords: ["甲状腺", "thyroid."]
        ),
        PanelMeta(
            id: "infection",
            title: "感染标志物",
            subtitle: "病毒抗体与核酸筛查",
            relatedSystems: ["免疫", "感染"],
            keywords: ["乙肝", "丙肝", "艾滋", "梅毒", "infect."]
        )
    ]

    static func inferPanelId(forMetricName name: String) -> String? {
        inferPanelId(forCanonicalKey: MetricNameCanonicalizer.canonicalKey(for: name))
            ?? inferPanelIdByKeyword(RiskAnalyzer.normalize(name))
    }

    static func inferPanelId(forCanonicalKey key: String) -> String? {
        if key.hasPrefix("lipid.") { return "lipid" }
        if key.hasPrefix("glucose.") { return "glucose" }
        if key.hasPrefix("liver.") { return "liver" }
        if key.hasPrefix("kidney.") { return "kidney" }
        if key.hasPrefix("blood.") { return "blood" }
        if key.hasPrefix("urine.") { return "urine" }
        if key.hasPrefix("gyn.") { return "gynecology" }
        if key.hasPrefix("coag.") { return "coagulation" }
        if key.hasPrefix("cardiac.") { return "cardiac" }
        if key.hasPrefix("thyroid.") { return "thyroid" }
        if key.hasPrefix("infect.") { return "infection" }
        return inferPanelIdByKeyword(key)
    }

    private static func inferPanelIdByKeyword(_ key: String) -> String? {
        for panel in panels {
            if panel.keywords.contains(where: { key.contains($0.lowercased()) }) {
                return panel.id
            }
        }
        return nil
    }

    static func classifyStatus(
        points: [HealthMetricTrendEngine.DataPoint],
        canonicalKey: String,
        metricTrend: MetricTrend
    ) -> HealthStatus {
        guard points.count >= 2 else { return .unclear }
        let sorted = points.sorted { $0.date < $1.date }
        let first = sorted.first!
        let last = sorted.last!

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

    private static func isImproving(
        first: HealthMetricTrendEngine.DataPoint,
        last: HealthMetricTrendEngine.DataPoint,
        trend: MetricTrend,
        canonicalKey: String
    ) -> Bool {
        guard first.value != 0, last.value != 0 else {
            return trend == .improving
        }
        let delta = last.value - first.value
        let lowerBetter = MetricNameCanonicalizer.isLowerBetter(canonicalKey: canonicalKey)
        if lowerBetter { return delta < -0.01 * first.value }
        return delta > 0.01 * first.value
    }

    static func metricMeta(forCanonicalKey key: String, fallbackName: String) -> MetricMeta {
        switch key {
        case "lipid.ldl":
            return MetricMeta(plainTitle: "坏胆固醇（LDL）", metricType: "血脂化验", relatedTo: "与动脉粥样硬化、心梗风险相关")
        case "lipid.hdl":
            return MetricMeta(plainTitle: "好胆固醇（HDL）", metricType: "血脂化验", relatedTo: "有助于清除血管脂质，偏低需关注")
        case "lipid.total_cholesterol":
            return MetricMeta(plainTitle: "总胆固醇", metricType: "血脂化验", relatedTo: "总体脂质水平，与心血管风险相关")
        case "lipid.triglycerides":
            return MetricMeta(plainTitle: "甘油三酯", metricType: "血脂化验", relatedTo: "与饮食、代谢综合征相关")
        case "lipid.non_hdl":
            return MetricMeta(plainTitle: "非高密度脂蛋白", metricType: "血脂化验", relatedTo: "残余胆固醇，与心血管风险相关")
        case "glucose.fasting":
            return MetricMeta(plainTitle: "空腹血糖", metricType: "糖代谢化验", relatedTo: "与糖尿病、胰岛素抵抗相关")
        case "glucose.hba1c":
            return MetricMeta(plainTitle: "糖化血红蛋白", metricType: "糖代谢化验", relatedTo: "反映近 2–3 个月平均血糖")
        case "liver.alt":
            return MetricMeta(plainTitle: "ALT（谷丙转氨酶）", metricType: "肝功能化验", relatedTo: "肝细胞损伤时可能升高")
        case "liver.ast":
            return MetricMeta(plainTitle: "AST（谷草转氨酶）", metricType: "肝功能化验", relatedTo: "肝、心、肌肉损伤时可升高")
        case "liver.ldh":
            return MetricMeta(plainTitle: "LDH（乳酸脱氢酶）", metricType: "肝功能化验", relatedTo: "组织细胞损伤时可能升高或偏低")
        case "liver.ggt":
            return MetricMeta(plainTitle: "GGT（γ-谷氨酰转肽酶）", metricType: "肝功能化验", relatedTo: "与胆道、饮酒等因素相关")
        case "kidney.uric_acid":
            return MetricMeta(plainTitle: "尿酸", metricType: "代谢化验", relatedTo: "与痛风、嘌呤代谢相关")
        case "kidney.creatinine":
            return MetricMeta(plainTitle: "肌酐", metricType: "肾功能化验", relatedTo: "反映肾脏滤过能力")
        case "kidney.urea":
            return MetricMeta(plainTitle: "尿素", metricType: "肾功能化验", relatedTo: "蛋白质代谢废物，受肾功能影响")
        case "blood.hemoglobin":
            return MetricMeta(plainTitle: "血红蛋白", metricType: "血常规", relatedTo: "与贫血、携氧能力相关")
        case "blood.wbc":
            return MetricMeta(plainTitle: "白细胞计数", metricType: "血常规", relatedTo: "与感染、免疫反应相关")
        case "blood.platelet":
            return MetricMeta(plainTitle: "血小板计数", metricType: "血常规", relatedTo: "与凝血、出血风险相关")
        case "urine.blood":
            return MetricMeta(plainTitle: "尿潜血", metricType: "尿常规", relatedTo: "与泌尿道、肾脏出血相关")
        case "gyn.h2o2":
            return MetricMeta(plainTitle: "阴道过氧化氢", metricType: "妇科检验", relatedTo: "反映阴道菌群平衡")
        case "gyn.leukocyte_esterase":
            return MetricMeta(plainTitle: "阴道白细胞酯酶", metricType: "妇科检验", relatedTo: "与阴道炎症相关")
        case "gyn.pus_cell":
            return MetricMeta(plainTitle: "阴道脓细胞", metricType: "妇科检验", relatedTo: "与阴道感染相关")
        default:
            return metricMeta(for: fallbackName)
        }
    }

    static func metricMeta(for name: String) -> MetricMeta {
        let key = RiskAnalyzer.normalize(name)
        if key.contains("白细胞") && !key.contains("尿") && !key.contains("阴道") {
            return MetricMeta(plainTitle: "白细胞", metricType: "血常规", relatedTo: "与感染、免疫反应相关")
        }
        return MetricMeta(
            plainTitle: name,
            metricType: "化验指标",
            relatedTo: "请结合体检报告与医生建议理解"
        )
    }
}
