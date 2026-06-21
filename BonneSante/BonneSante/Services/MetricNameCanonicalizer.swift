import Foundation

/// 跨报告指标名称归一（仁济等不同年份命名对齐）
/// @author jiali.qiu
enum MetricNameCanonicalizer {

    /// 模糊对齐结果（供档案合并与校对提示）
    struct Resolution {
        let canonicalKey: String
        let displayName: String
        /// 0…1，越高表示越确信
        let confidence: Double
    }

    private struct CatalogEntry {
        let key: String
        let display: String
        let tokens: [String]
    }

    /// 同义词库：支持缩写、英文、OCR 异写、不同医院命名
    private static let catalog: [CatalogEntry] = [
        CatalogEntry(key: "lipid.ldl", display: "低密度脂蛋白", tokens: ["低密度", "ldl", "ldlc", "坏胆固醇"]),
        CatalogEntry(key: "lipid.hdl", display: "高密度脂蛋白", tokens: ["高密度", "hdl", "hdlc", "好胆固醇"]),
        CatalogEntry(key: "lipid.total_cholesterol", display: "总胆固醇", tokens: ["总胆固醇", "tc", "胆固醇"]),
        CatalogEntry(key: "lipid.triglycerides", display: "甘油三酯", tokens: ["甘油三酯", "tg", "三酰甘油"]),
        CatalogEntry(key: "glucose.fasting", display: "空腹血糖", tokens: ["空腹血糖", "空腹葡萄糖", "fbg", "glu"]),
        CatalogEntry(key: "glucose.hba1c", display: "糖化血红蛋白", tokens: ["糖化血红蛋白", "hba1c", "糖化"]),
        CatalogEntry(key: "liver.alt", display: "ALT（谷丙转氨酶）", tokens: ["丙氨酸氨基转移酶", "谷丙转氨酶", "alt"]),
        CatalogEntry(key: "liver.ast", display: "AST（谷草转氨酶）", tokens: ["天门冬氨酸氨基转移酶", "门冬氨酸氨基转移酶", "谷草转氨酶", "ast"]),
        CatalogEntry(key: "liver.ggt", display: "GGT（γ-谷氨酰转肽酶）", tokens: ["谷氨酰转肽酶", "ggt", "ygt"]),
        CatalogEntry(key: "liver.ldh", display: "LDH（乳酸脱氢酶）", tokens: ["乳酸脱氢酶", "ldh"]),
        CatalogEntry(key: "liver.total_bilirubin", display: "总胆红素", tokens: ["总胆红素", "tbil"]),
        CatalogEntry(key: "liver.direct_bilirubin", display: "直接胆红素", tokens: ["直接胆红素", "dbil"]),
        CatalogEntry(key: "kidney.creatinine", display: "肌酐", tokens: ["肌酐", "crea", "cr"]),
        CatalogEntry(key: "kidney.urea", display: "尿素", tokens: ["尿素", "尿素氮", "bun"]),
        CatalogEntry(key: "kidney.uric_acid", display: "尿酸", tokens: ["尿酸", "ua"]),
        CatalogEntry(key: "blood.hemoglobin", display: "血红蛋白", tokens: ["血红蛋白", "hb", "hgb", "血色素"]),
        CatalogEntry(key: "blood.rbc", display: "红细胞计数", tokens: ["红细胞计数", "红细胞", "rbc"]),
        CatalogEntry(key: "blood.wbc", display: "白细胞计数", tokens: ["白细胞计数", "白细胞", "wbc"]),
        CatalogEntry(key: "blood.platelet", display: "血小板计数", tokens: ["血小板计数", "血小板", "plt"]),
        CatalogEntry(key: "coag.pt", display: "凝血酶原时间", tokens: ["凝血酶原时间", "pt", "凝血酶原"]),
        CatalogEntry(key: "coag.aptt", display: "活化部分凝血活酶时间", tokens: ["活化部分凝血活酶时间", "aptt"]),
        CatalogEntry(key: "coag.d_dimer", display: "D-二聚体", tokens: ["d二聚体", "d-二聚体", "ddimer"]),
        CatalogEntry(key: "coag.fibrinogen", display: "纤维蛋白原", tokens: ["纤维蛋白原", "fib"]),
        CatalogEntry(key: "coag.inr", display: "国际标准化比值", tokens: ["国际标准化比值", "inr"]),
        CatalogEntry(key: "cardiac.troponin", display: "心肌肌钙蛋白", tokens: ["肌钙蛋白", "troponin", "ctni"]),
        CatalogEntry(key: "cardiac.bnp", display: "氨基末端利钠肽前体", tokens: ["利钠肽", "bnp", "ntprobnp"]),
        CatalogEntry(key: "thyroid.tsh", display: "促甲状腺激素", tokens: ["促甲状腺激素", "tsh"]),
        CatalogEntry(key: "thyroid.ft3", display: "游离三碘甲状腺原氨酸", tokens: ["游离三碘甲状腺原氨酸", "ft3"]),
        CatalogEntry(key: "thyroid.ft4", display: "游离甲状腺素", tokens: ["游离甲状腺素", "ft4"]),
        CatalogEntry(key: "thyroid.t3", display: "三碘甲状腺原氨酸", tokens: ["三碘甲状腺原氨酸", "t3"]),
        CatalogEntry(key: "thyroid.t4", display: "甲状腺素", tokens: ["甲状腺素", "t4"]),
        CatalogEntry(key: "infect.hbsag", display: "乙肝表面抗原", tokens: ["乙肝表面抗原", "hbsag"]),
        CatalogEntry(key: "infect.hbsab", display: "乙肝表面抗体", tokens: ["乙肝表面抗体", "hbsab"]),
        CatalogEntry(key: "urine.blood", display: "尿潜血", tokens: ["尿潜血", "尿隐血", "ery"]),
        CatalogEntry(key: "urine.protein", display: "尿蛋白", tokens: ["尿蛋白", "pro"]),
        CatalogEntry(key: "tumor.afp", display: "甲胎蛋白", tokens: ["甲胎蛋白", "afp"]),
        CatalogEntry(key: "tumor.cea", display: "癌胚抗原", tokens: ["癌胚抗原", "cea"])
    ]

    /// 智能解析：先精确规则，再同义词模糊匹配
    static func resolve(_ rawName: String) -> Resolution {
        let trimmed = rawName.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        guard trimmed.count >= 2 else {
            return Resolution(canonicalKey: "raw.", displayName: trimmed, confidence: 0)
        }

        let directKey = canonicalKeyStrict(for: trimmed)
        if !directKey.hasPrefix("raw.") {
            let display = catalog.first(where: { $0.key == directKey })?.display
                ?? MetricTrendCatalog.metricMeta(forCanonicalKey: directKey, fallbackName: trimmed).plainTitle
            return Resolution(canonicalKey: directKey, displayName: display, confidence: 1)
        }

        let normalized = RiskAnalyzer.normalize(trimmed)
        var bestScore = 0.0
        var bestEntry: CatalogEntry?

        for entry in catalog {
            let score = matchScore(normalized: normalized, tokens: entry.tokens)
            if score > bestScore {
                bestScore = score
                bestEntry = entry
            }
        }

        if let bestEntry, bestScore >= 0.42 {
            return Resolution(canonicalKey: bestEntry.key, displayName: bestEntry.display, confidence: bestScore)
        }

        return Resolution(canonicalKey: directKey, displayName: trimmed, confidence: 0)
    }

    /// 对外统一入口：精确 + 模糊
    static func canonicalKey(for name: String) -> String {
        let resolution = resolve(name)
        if resolution.confidence >= 0.42, !resolution.canonicalKey.hasPrefix("raw.") {
            return resolution.canonicalKey
        }
        return canonicalKeyStrict(for: name)
    }

    /// 仅规则匹配，不做模糊
    static func canonicalKeyStrict(for name: String) -> String {
        let k = RiskAnalyzer.normalize(name)

        if k.contains("非高密度") { return "lipid.non_hdl" }
        if k.contains("低密度") || k.contains("ldl") { return "lipid.ldl" }
        if k.contains("高密度") || k.contains("hdl") { return "lipid.hdl" }
        if k.contains("甘油三酯") { return "lipid.triglycerides" }
        if k.contains("总胆固醇") { return "lipid.total_cholesterol" }

        if k.contains("糖化") { return "glucose.hba1c" }
        if k.contains("空腹") && (k.contains("糖") || k.contains("葡萄糖")) { return "glucose.fasting" }

        if k.contains("乳酸脱氢") || k == "ldh" { return "liver.ldh" }
        if k.contains("丙氨酸") || k == "alt" { return "liver.alt" }
        if k.contains("天门冬") || k == "ast" { return "liver.ast" }
        if k.contains("谷氨酰") || k.contains("ggt") { return "liver.ggt" }
        if k.contains("碱性磷酸") { return "liver.alp" }
        if k.contains("直接胆红素") { return "liver.direct_bilirubin" }
        if k.contains("总胆红素") { return "liver.total_bilirubin" }

        if k.contains("egfr") { return "kidney.egfr" }
        if k.contains("尿素") { return "kidney.urea" }
        if k.contains("肌酐") { return "kidney.creatinine" }
        if k.contains("尿酸") && !k.contains("酸碱") { return "kidney.uric_acid" }

        if k.contains("血红蛋白") && !k.contains("浓度") && !k.contains("平均") { return "blood.hemoglobin" }
        if k.contains("血小板计数") || (k.contains("血小板") && k.contains("计数")) { return "blood.platelet" }
        if k.contains("红细胞计数") { return "blood.rbc" }
        if k.contains("白细胞计数") { return "blood.wbc" }

        if k.contains("凝血酶原") || k.contains("凝血酶时间") { return "coag.pt" }
        if k.contains("活化部分凝血") { return "coag.aptt" }
        if k.contains("纤维蛋白原") { return "coag.fibrinogen" }
        if k.contains("国际标准化") || k == "inr" { return "coag.inr" }
        if k.contains("二聚体") { return "coag.d_dimer" }

        if k.contains("肌钙蛋白") { return "cardiac.troponin" }
        if k.contains("肌酸激酶") { return "cardiac.ckmb" }
        if k.contains("利钠肽") { return "cardiac.bnp" }
        if k.contains("肌红蛋白") { return "cardiac.myoglobin" }
        if k.contains("降钙素原") { return "cardiac.pct" }

        if k.contains("促甲状腺激素") || k == "tsh" { return "thyroid.tsh" }
        if k.contains("游离三碘") || k == "ft3" { return "thyroid.ft3" }
        if k.contains("游离甲状腺") || k == "ft4" { return "thyroid.ft4" }
        if k.contains("三碘甲状腺") && !k.contains("游离") { return "thyroid.t3" }
        if k.contains("甲状腺素") && !k.contains("游离") { return "thyroid.t4" }
        if k.contains("甲状腺球蛋白抗体") { return "thyroid.tgab" }
        if k.contains("过氧化物酶抗体") { return "thyroid.tpoab" }

        if k.contains("乙肝") && k.contains("表面抗原") { return "infect.hbsag" }
        if k.contains("乙肝") && k.contains("表面抗体") { return "infect.hbsab" }
        if k.contains("乙肝") && k.contains("e抗原") { return "infect.hbeag" }
        if k.contains("乙肝") && k.contains("核心抗体") { return "infect.hbcab" }
        if k.contains("乙肝") && k.contains("核酸") { return "infect.hbv_dna" }
        if k.contains("丙肝") { return "infect.hcv" }

        if k.contains("尿潜血") || k.contains("尿隐血") || k.contains("ery") { return "urine.blood" }
        if k.contains("尿蛋白") { return "urine.protein" }
        if k.contains("尿白细胞") || k.contains("leu") { return "urine.wbc" }

        if k.contains("阴道分泌物") && k.contains("过氧化氢") { return "gyn.h2o2" }
        if k.contains("阴道分泌物") && (k.contains("脂酶") || k.contains("酯酶")) { return "gyn.leukocyte_esterase" }
        if k.contains("阴道分泌物") && k.contains("脓细胞") { return "gyn.pus_cell" }

        if k.contains("甲胎蛋白") || k == "afp" { return "tumor.afp" }
        if k.contains("癌胚抗原") || k == "cea" { return "tumor.cea" }
        if k.contains("ca19") { return "tumor.ca199" }

        return "raw.\(k)"
    }

    /// 数值越低通常越好（用于「好转中」判断）
    static func isLowerBetter(canonicalKey: String) -> Bool {
        if canonicalKey.hasPrefix("lipid.") && canonicalKey != "lipid.hdl" { return true }
        switch canonicalKey {
        case "lipid.hdl", "blood.hemoglobin", "blood.platelet", "blood.rbc", "blood.wbc",
             "kidney.egfr":
            return false
        default:
            return true
        }
    }

    // MARK: - Fuzzy

    private static func matchScore(normalized: String, tokens: [String]) -> Double {
        var best = 0.0
        for token in tokens {
            let t = RiskAnalyzer.normalize(token)
            guard t.count >= 2 else { continue }
            if normalized == t {
                best = max(best, 1.0)
            } else if normalized.contains(t) || t.contains(normalized) {
                let ratio = Double(min(normalized.count, t.count)) / Double(max(normalized.count, t.count))
                best = max(best, 0.55 + ratio * 0.35)
            }
        }
        return best
    }
}
