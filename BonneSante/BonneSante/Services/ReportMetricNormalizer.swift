import Foundation

/// 体检指标名称/单位规范化与参考范围异常判定
/// @author jiali.qiu
enum ReportMetricNormalizer {

    private static let unitCorrections: [(String, String)] = [
        ("mmo1/l", "mmol/L"), ("mno1/l", "mmol/L"), ("mnol/l", "mmol/L"), ("mm.o1/l", "mmol/L"),
        ("hmol/l", "μmol/L"), ("hmo1/l", "μmol/L"), ("μmol/l", "μmol/L"),
        ("mnhig", "mmHg"), ("mnlig", "mmHg"), ("mnhg", "mmHg"),
        ("u/l", "U/L"), ("g/l", "g/L"), ("s/l", "g/L"), ("ng/m", "ng/mL"),
        ("u/ml", "U/mL"), ("au/ml", "AU/mL"), ("x10^9/l", "×10^9/L"),
        ("x10^12/l", "×10^12/L"), ("x109/l", "×10^9/L"), ("munv/h", "mm/h"),
        ("mn.1/l", "mmol/L"), ("nmol/l", "nmol/L"), ("/epf", "/EP"), ("/ep", "/EP")
    ]

    private static let nameAliases: [String: String] = [
        "低密度脂蛋白": "低密度脂蛋白",
        "ldl": "低密度脂蛋白",
        "ldl-c": "低密度脂蛋白",
        "高密度脂蛋白": "高密度脂蛋白",
        "hdl": "高密度脂蛋白",
        "总胆固醇": "总胆固醇",
        "tc": "总胆固醇",
        "甘油三酯": "甘油三酯",
        "tg": "甘油三酯",
        "y-谷氨酰转肽酶": "γ-谷氨酰转肽酶",
        "γ-谷氨酰转肽酶": "γ-谷氨酰转肽酶",
        "天门冬氨酸氨基转移酶": "天门冬氨酸氨基转移酶（AST）",
        "ast": "天门冬氨酸氨基转移酶（AST）",
        "丙氨酸氨基转移酶": "丙氨酸氨基转移酶（ALT）",
        "alt": "丙氨酸氨基转移酶（ALT）",
        "乳酸脱氢酶": "乳酸脱氢酶",
        "ldh": "乳酸脱氢酶",
        "空腹血糖": "空腹血糖",
        "白细胞计数": "白细胞计数",
        "血红蛋白": "血红蛋白",
        "尿酸": "尿酸",
        "肌酐": "肌酐",
        "尿素氮": "尿素氮",
        "脓细胞": "脓细胞",
        "门冬氨酸氨基转移酶": "天门冬氨酸氨基转移酶（AST）",
        "促甲状腺激素": "促甲状腺激素",
        "游离甲状腺素": "游离甲状腺素",
        "游离三碘甲状腺原氨酸": "游离三碘甲状腺原氨酸",
        "三碘甲状腺原氨酸": "三碘甲状腺原氨酸",
        "甲状腺素": "甲状腺素",
        "d-二聚体": "D-二聚体",
        "胆甾醇": "胆碱酯酶",
        "胆碱酯酶": "胆碱酯酶",
        "心肌肌钙蛋白t": "心肌肌钙蛋白T",
        "蛋白电泳alb": "蛋白电泳Alb",
        "蛋白电泳α2": "蛋白电泳α2"
    ]

    /// 规范化指标名称（去空格、统一别名）
    static func normalizeName(_ name: String) -> String {
        let trimmed = name
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "")
        let key = trimmed.lowercased()
        if let alias = nameAliases[key] { return alias }
        for (k, v) in nameAliases where key.contains(k) { return v }
        return trimmed
    }

    /// 规范化单位字符串
    static func normalizeUnit(_ unit: String) -> String {
        let lower = unit.trimmingCharacters(in: .whitespaces).lowercased()
        guard !lower.isEmpty else { return unit }
        for (wrong, correct) in unitCorrections where lower.contains(wrong) {
            return correct
        }
        return unit.trimmingCharacters(in: .whitespaces)
    }

    /// 从 valueText 中提取并纠正单位
    static func extractAndFixUnit(from valueText: String, explicitUnit: String) -> String {
        if !explicitUnit.isEmpty { return normalizeUnit(explicitUnit) }
        let known = ["mmol/L", "μmol/L", "U/L", "g/L", "mmHg", "AU/mL", "ng/mL", "×10^9/L", "×10^12/L", "%", "/EP", "mm/h"]
        for u in known where valueText.localizedCaseInsensitiveContains(u) { return u }
        let lower = valueText.lowercased()
        for (wrong, correct) in unitCorrections where lower.contains(wrong) { return correct }
        return explicitUnit
    }

    /// 判断名称是否像有效检验指标（过滤 OCR 误报）
    static func isLikelyLabMetricName(_ name: String) -> Bool {
        let n = name.trimmingCharacters(in: .whitespaces)
        guard (2...40).contains(n.count) else { return false }

        if isTimestampLike(n) { return false }
        if isPanelHeader(n) { return false }

        let reject = [
            "电话", "联系电话", "医师", "评估日期", "审核时间", "日税", "参日税", "段和", "存在100",
            "兼有健康", "项目名称", "检验报告", "第", "页/共", "体检编号", "检查医生",
            "糖类抗原（ca", "ca19", "审核者", "审校者", "检验者", "性别", "年龄", "姓名",
            "工号", "部门", "进别", "料室", "采完时间", "门诊号", "住洗号", "心电图报告"
        ]
        let lower = n.lowercased()
        if reject.contains(where: { lower.contains($0.lowercased()) }) { return false }
        if n.contains("检查部位") || n.contains("检查所见") || n.contains("检查描述") { return false }
        if n.contains("**") || n.hasPrefix("#") { return false }
        if n.range(of: #"[\u4e00-\u9fa5]{2,}"#, options: .regularExpression) == nil { return false }
        if n.range(of: #"\d{6,}"#, options: .regularExpression) != nil { return false }
        if n.contains("（Te") || n.contains("：135") { return false }
        return true
    }

    /// 审核时间等误识别
    static func isTimestampLike(_ text: String) -> Bool {
        let t = text.replacingOccurrences(of: " ", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return false }
        if t.range(of: #"^20\d{10,}"#, options: .regularExpression) != nil { return true }
        if t.range(of: #"^\d{8,}:\d{2}"#, options: .regularExpression) != nil { return true }
        if t.range(of: #"^\d{12,}$"#, options: .regularExpression) != nil { return true }
        return false
    }

    /// 检验组合/小节标题，不是具体指标
    static func isPanelHeader(_ name: String) -> Bool {
        let n = name.trimmingCharacters(in: .whitespaces)
        if n.hasSuffix("检验）") || n.hasSuffix("检验)") { return true }
        if n.contains("审核者") || n.contains("审校者") { return true }
        if n.hasSuffix("组合") && !n.contains("抗原") { return true }
        if n.contains("EGFR+") || n.contains("EGFR＋") { return true }
        if n.contains("血液化学检验") || n.contains("临床血液") { return true }
        if n.contains("尿液分析组合") || n.contains("阴道分泌物常规组合") { return true }
        let clinicPanels = [
            "凝血功能", "心脏标志物", "感染性标志物", "病毒抗体", "生化", "血常规",
            "甲状腺功能", "免疫组", "未知时间", "检验", "影像", "心电图"
        ]
        if clinicPanels.contains(where: { n == $0 || n.hasSuffix($0) }) { return true }
        if n.range(of: #"^\d{4}年$"#, options: .regularExpression) != nil { return true }
        return false
    }

    /// 校验指标名称 + 结果是否合理
    static func isValidMetric(_ metric: ReportImporter.DraftMetric) -> Bool {
        guard isLikelyLabMetricName(metric.name) else { return false }
        guard !isPanelHeader(metric.name) else { return false }

        let valueText = metric.valueText.trimmingCharacters(in: .whitespaces)
        if isTimestampLike(valueText) { return false }
        if valueText.range(of: #"\d{8,}"#, options: .regularExpression) != nil { return false }

        // 参考范围被误填为结果
        if valueText.range(of: #"^\d+\.?\d*\s*-\s*\d+\.?\d*$"#, options: .regularExpression) != nil {
            return false
        }

        // 定性结果（阳性/阴性/未见）保留，纯文字无数字也可
        let qualitative = ["阳性", "阴性", "正常", "未见", "未查见", "低于检出", "I", "II", "III", "IV"]
        if qualitative.contains(where: { valueText.contains($0) }) && metric.value == 0 {
            return true
        }

        // 需有有效数值
        if metric.value == 0 && valueText.filter({ $0.isNumber }).isEmpty { return false }

        // 尿酸碱度误标为尿酸
        if metric.name == "尿酸", metric.value > 0, metric.value < 30, !valueText.contains("μmol") {
            return false
        }

        // 血压合理范围
        if metric.name.contains("收缩压"), metric.value > 0, metric.value < 60 || metric.value > 250 {
            return false
        }
        if metric.name.contains("舒张压"), metric.value > 0, metric.value < 30 || metric.value > 150 {
            return false
        }

        // 血红蛋白不可能 > 200（多为 MCHC 误标，已在 polish 中纠正）
        if metric.name.contains("血红蛋白"), !metric.name.contains("浓度"), !metric.name.contains("含"),
           metric.value > 200, metric.value < 280 { return false }

        return true
    }

    /// 过滤 + 去重
    static func filterMetrics(_ metrics: [ReportImporter.DraftMetric]) -> [ReportImporter.DraftMetric] {
        var seen = Set<String>()
        var result: [ReportImporter.DraftMetric] = []
        for var item in metrics {
            item = polish(item)
            guard isValidMetric(item) else { continue }
            let key = normalizeName(item.name).lowercased()
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            result.append(item)
        }
        return result
    }

    /// 异常发现去重（小叶增生等）
    static func dedupeFindings(_ findings: [ReportImporter.DraftFinding]) -> [ReportImporter.DraftFinding] {
        var seen = Set<String>()
        var result: [ReportImporter.DraftFinding] = []
        for var item in findings {
            if isInsignificantImagingLine(item.title) && isInsignificantImagingLine(item.detail.isEmpty ? item.title : item.detail) {
                continue
            }
            item = normalizeFindingPresentation(item)
            guard !item.title.trimmingCharacters(in: CharacterSet.whitespaces).isEmpty else { continue }
            let dateKey = item.visitDate.map { ReportDisplayFormatter.examDateLabel($0) } ?? ""
            let key = dateKey + "|" + item.title
                .replacingOccurrences(of: "双侧", with: "")
                .replacingOccurrences(of: "双", with: "")
                .replacingOccurrences(of: " ", with: "")
                .lowercased()
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            result.append(item)
        }
        return result
    }

    /// 过滤门诊 Markdown 解析产生的无效结论（字段标签、注释行等）
    static func isJunkClinicFinding(_ finding: ReportImporter.DraftFinding) -> Bool {
        let title = finding.title.trimmingCharacters(in: CharacterSet.whitespaces)
        if title.isEmpty { return true }
        if title.count < 3, !hasClinicalFindingContent(finding) { return true }
        let stripped = title
            .replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "：", with: "")
            .replacingOccurrences(of: ":", with: "")
            .trimmingCharacters(in: CharacterSet.whitespaces)
        let fieldOnly = ["检查部位", "检查描述", "检查所见", "诊断结论"]
        if fieldOnly.contains(stripped) { return true }
        if title.contains("检查部位") && title.count < 12 { return true }
        if title.hasPrefix("*注") || title.contains("参考区间显示") { return true }
        if title.hasPrefix("#") { return true }
        return false
    }

    /// 短标题（如「肝脏」「乳腺」）是否有足够临床内容，避免误杀
    static func hasClinicalFindingContent(_ finding: ReportImporter.DraftFinding) -> Bool {
        if finding.isAbnormal || finding.severityRank > 0 { return true }
        if !finding.conclusion.trimmingCharacters(in: CharacterSet.whitespaces).isEmpty { return true }
        if !finding.detail.trimmingCharacters(in: CharacterSet.whitespaces).isEmpty { return true }
        if !finding.morphology.isEmpty || !finding.organSite.isEmpty { return true }
        let tags = finding.taxonomyTags
        return tags.morphology != .other || tags.organSite != .other
    }

    /// 两字器官名（肺部/肝脏等）在异常发现里很常见，不能仅因长度跳过
    private static let shortOrganTitles: Set<String> = [
        "肺", "肺部", "肝", "肝脏", "心", "心脏", "肾", "肾脏", "胆", "胆囊",
        "脾", "脾脏", "胰", "胰腺", "胸", "胸部", "甲状腺", "乳腺", "子宫", "宫颈"
    ]

    /// 过滤门诊影像中的正常/阴性描述（无需入库为异常发现）
    static func isInsignificantImagingLine(_ text: String) -> Bool {
        let t = text.trimmingCharacters(in: CharacterSet.whitespaces)
        if t.count < 3 {
            return !shortOrganTitles.contains(t)
        }

        let pathologyKeywords = [
            "结节", "磨玻璃", "占位", "血管瘤", "fnh", "增生", "囊肿", "结石",
            "增厚", "扩大", "异常信号", "低回声", "高回声", "斑块", "狭窄",
            "水肿", "破坏", "骨折", "阴影"
        ]
        let hasPathology = pathologyKeywords.contains { t.localizedCaseInsensitiveContains($0) }

        let normalPhrases = [
            "未见异常", "未见明显异常", "未见肿大", "未见明显", "无殊", "无异常",
            "无胸腔积液", "无腹水", "结构清楚", "纵隔居中", "未见积液",
            "未见扩大", "未见破坏", "未见占位", "未见结石"
        ]
        let looksNormal = normalPhrases.contains { t.contains($0) }

        if looksNormal && !hasPathology { return true }
        if t.hasPrefix("双侧") && t.contains("未见") && !hasPathology { return true }
        return false
    }

    /// 整理发现项展示，避免标题与详情重复
    static func normalizeFindingPresentation(_ finding: ReportImporter.DraftFinding) -> ReportImporter.DraftFinding {
        var copy = finding
        var title = copy.title.trimmingCharacters(in: CharacterSet.whitespaces)
        var detail = copy.detail.trimmingCharacters(in: CharacterSet.whitespaces)

        if detail == title {
            detail = ""
        } else if !detail.isEmpty, detail.hasPrefix(title), detail.count - title.count < 4,
                  !hasClinicalFindingContent(copy) {
            detail = ""
        } else if !title.isEmpty, title.count > 8, detail.contains(title) {
            detail = detail.replacingOccurrences(of: title, with: "")
                .trimmingCharacters(in: CharacterSet.whitespaces)
        }

        if (title == "影像" || title == "胸部影像" || title == "腹部影像"), !detail.isEmpty {
            let full = finding.detail.trimmingCharacters(in: CharacterSet.whitespaces)
            title = full.count <= 28 ? full : String(full.prefix(28)) + "…"
            detail = full.count <= 28 ? "" : full
        }

        copy.title = title
        copy.detail = detail == title ? "" : detail
        return copy
    }

    /// 拆分心电图参数与结论，并为正常项补全 assessmentNote
    static func enrichClinicalFinding(_ finding: ReportImporter.DraftFinding) -> ReportImporter.DraftFinding {
        var copy = finding
        let blob = (copy.title + " " + copy.detail).trimmingCharacters(in: CharacterSet.whitespaces)

        if ClinicalFindingParser.isECGRelated(copy) {
            copy.category = "心电图"
            copy.title = "心电图"
            let source = copy.detail.isEmpty ? blob : copy.detail
            let split = ClinicalFindingParser.splitECG(source)
            copy.detail = split.parameters
            var conclusion = split.conclusion
            if conclusion.isEmpty {
                conclusion = copy.conclusion.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            }
            if !conclusion.isEmpty {
                copy.conclusion = conclusion
                copy.isAbnormal = !ClinicalFindingParser.isNormalECGConclusion(conclusion)
                syncConclusionNote(&copy)
            }
        } else if let conclusion = ClinicalFindingParser.extractTrailingConclusion(from: blob), !conclusion.isEmpty {
            if copy.conclusion.isEmpty { copy.conclusion = conclusion }
            syncConclusionNote(&copy)
            if !copy.isAbnormal, copy.detail.contains(conclusion) {
                copy.detail = copy.detail
                    .replacingOccurrences(of: conclusion, with: "")
                    .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "。."))
            }
        } else if !copy.conclusion.isEmpty {
            syncConclusionNote(&copy)
        }

        if copy.assessmentNote.isEmpty, !copy.isAbnormal {
            copy.assessmentNote = AbnormalitySeverityRanker.localAssessmentNote(
                name: copy.title,
                detail: copy.detail,
                isAbnormal: false,
                severityRank: 0
            )
        }

        if copy.morphology.isEmpty || copy.organSite.isEmpty {
            let blob = (copy.title + " " + copy.detail + " " + copy.conclusion).trimmingCharacters(in: .whitespaces)
            let inferred = ClinicalFindingTaxonomy.inferFromText(blob)
            if copy.morphology.isEmpty, inferred.morphology != .other {
                copy.morphology = inferred.morphology.rawValue
            }
            if copy.organSite.isEmpty, inferred.organSite != .other {
                copy.organSite = inferred.organSite.rawValue
            }
        }

        return normalizeFindingPresentation(copy)
    }

    /// 将 conclusion 同步到 assessmentNote；若已有通用占位文案则覆盖为真实结论
    private static func syncConclusionNote(_ finding: inout ReportImporter.DraftFinding) {
        let conclusion = finding.conclusion.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        guard !conclusion.isEmpty else { return }
        let note = "结论：\(conclusion)"
        if finding.assessmentNote.isEmpty || isPlaceholderAssessmentNote(finding.assessmentNote) {
            finding.assessmentNote = note
        } else if !finding.assessmentNote.contains(conclusion) {
            finding.assessmentNote = dedupeAssessmentNote("\(finding.assessmentNote)；\(note)")
        }
    }

    /// 合并 assessmentNote 时去除重复分句（；分隔）
    static func dedupeAssessmentNote(_ note: String) -> String {
        let trimmed = note.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        let parts = trimmed
            .components(separatedBy: CharacterSet(charactersIn: "；;"))
            .map { $0.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var seen = Set<String>()
        var unique: [String] = []
        for part in parts {
            let normalized = RiskAnalyzer.normalize(part)
            if seen.insert(normalized).inserted {
                unique.append(part)
            }
        }
        return unique.joined(separator: "；")
    }

    /// 是否为本地兜底占位文案（应在提取到真实结论后覆盖）
    static func isPlaceholderAssessmentNote(_ note: String) -> Bool {
        let trimmed = note.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        return trimmed == "未见明显异常，待同项复查对比"
            || trimmed == AbnormalitySeverityRanker.localAssessmentNote(
                name: "", detail: "", isAbnormal: false, severityRank: 0
            )
    }

    /// 根据数值、参考范围、行内标记推断是否异常
    static func inferAbnormal(
        value: Double,
        referenceRange: String,
        lineHint: String = "",
        explicitFlag: Bool = false
    ) -> Bool {
        if explicitFlag { return true }
        let hint = lineHint + referenceRange
        if hint.contains("↑") || hint.contains("↓") || hint.contains("偏高") || hint.contains("偏低") { return true }
        if hint.contains(" H") || hint.contains(" L") || hint.contains("阳性") && !hint.contains("阴性") { return true }

        let ref = referenceRange.trimmingCharacters(in: .whitespaces)
        guard !ref.isEmpty, value != 0 else { return explicitFlag }

        if let threshold = parseLessThan(ref), value >= threshold { return true }
        if let threshold = parseGreaterThan(ref), value <= threshold { return true }
        if let (low, high) = parseRange(ref) {
            if value < low || value > high { return true }
        }
        return false
    }

    /// 推断数值相对参考范围或原文标记的偏高/偏低箭头（↑ / ↓）
    static func inferTrendArrow(
        value: Double,
        referenceRange: String,
        lineHint: String = ""
    ) -> String? {
        let hint = lineHint
        if hint.contains("↑") || hint.contains("偏高") || hint.contains("升高")
            || hint.contains("超标") || hint.contains("轻度升高") || hint.contains(" H") {
            return "↑"
        }
        if hint.contains("↓") || hint.contains("偏低") || hint.contains("降低") || hint.contains(" L") {
            return "↓"
        }
        if hint.contains("+") && !hint.contains("+-") && !hint.lowercased().contains("neg") { return "↑" }
        if hint.contains("阳性") && !hint.contains("阴性") { return "↑" }

        let ref = referenceRange.trimmingCharacters(in: .whitespaces)
        guard !ref.isEmpty, value != 0 else { return nil }

        if let threshold = parseLessThan(ref) {
            if value >= threshold { return "↑" }
            return "↓"
        }
        if let threshold = parseGreaterThan(ref) {
            if value <= threshold { return "↓" }
            return "↑"
        }
        if let (low, high) = parseRange(ref) {
            if value > high { return "↑" }
            if value < low { return "↓" }
        }
        return nil
    }

    /// 对 DraftMetric 应用规范化与异常推断
    static func polish(_ metric: ReportImporter.DraftMetric, lineHint: String = "") -> ReportImporter.DraftMetric {
        var m = metric
        m.name = normalizeName(m.name)
        repairMislabeled(&m, lineHint: lineHint)
        m.unit = extractAndFixUnit(from: m.valueText, explicitUnit: normalizeUnit(m.unit))
        if !m.unit.isEmpty, !m.valueText.localizedCaseInsensitiveContains(m.unit) {
            m.valueText = "\(trimNumeric(m.valueText)) \(m.unit)".trimmingCharacters(in: .whitespaces)
        }
        m.isAbnormal = inferAbnormal(
            value: m.value,
            referenceRange: m.referenceRange,
            lineHint: lineHint + m.valueText,
            explicitFlag: m.isAbnormal
        )
        return m
    }

    /// 纠正 OCR 常见错标（血压拆字、MCHC 误标为血红蛋白）
    private static func repairMislabeled(_ metric: inout ReportImporter.DraftMetric, lineHint: String) {
        if metric.name.contains("收缩压"), metric.value >= 10, metric.value < 60 {
            if let fixed = extractRegexDouble(from: lineHint, pattern: #"收缩压\s+(\d{2,3})"#) {
                metric.value = fixed
                metric.valueText = metric.unit.isEmpty ? String(fixed) : "\(fixed) \(metric.unit)"
            }
        }
        if metric.name.contains("血红蛋白"), !metric.name.contains("浓度"), !metric.name.contains("含"),
           metric.value >= 280 {
            metric.name = "平均血红蛋白浓度"
        }
    }

    private static func extractRegexDouble(from text: String, pattern: String) -> Double? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else { return nil }
        return Double(text[range])
    }

    // MARK: - Reference parsing

    private static func parseRange(_ ref: String) -> (Double, Double)? {
        let cleaned = ref.replacingOccurrences(of: "～", with: "~").replacingOccurrences(of: "—", with: "-")
        guard let match = cleaned.range(of: #"([\d.]+)\s*[-~]\s*([\d.]+)"#, options: .regularExpression) else {
            return nil
        }
        let segment = String(cleaned[match])
        let parts = segment.components(separatedBy: CharacterSet(charactersIn: "-~"))
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .compactMap { Double($0) }
        guard parts.count == 2 else { return nil }
        return (min(parts[0], parts[1]), max(parts[0], parts[1]))
    }

    private static func parseLessThan(_ ref: String) -> Double? {
        guard let match = ref.range(of: #"[<≤]\s*([\d.]+)"#, options: .regularExpression) else { return nil }
        let segment = String(ref[match])
        return Double(segment.filter { $0.isNumber || $0 == "." })
    }

    private static func parseGreaterThan(_ ref: String) -> Double? {
        guard let match = ref.range(of: #"[>≥]\s*([\d.]+)"#, options: .regularExpression) else { return nil }
        let segment = String(ref[match])
        return Double(segment.filter { $0.isNumber || $0 == "." })
    }

    private static func trimNumeric(_ text: String) -> String {
        String(text.prefix(while: { $0.isNumber || $0 == "." }))
    }
}

/// 心电图等功能性结论解析
/// @author jiali.qiu
enum ClinicalFindingParser {

    private static let ecgConclusions = [
        "正常心电图", "大致正常心电图", "异常心电图", "窦性心律", "窦性心动过缓",
        "窦性心动过速", "房性早搏", "室性早搏", "ST-T改变", "T波改变", "左心室高电压"
    ]

    private static let normalImagingPhrases = [
        "未见明显异常", "未见异常", "目前未见明显异常", "目前未见异常", "未见肿大"
    ]

    static func isECGRelated(_ finding: ReportImporter.DraftFinding) -> Bool {
        let blob = RiskAnalyzer.normalize(finding.title + finding.detail + finding.category)
        return blob.contains("心电图") || blob.contains("qt") || blob.contains("qrs")
            || (blob.contains("心率") && blob.contains("bpm"))
    }

    static func splitECG(_ text: String) -> (parameters: String, conclusion: String) {
        let trimmed = text.trimmingCharacters(in: CharacterSet.whitespaces)
        for marker in ecgConclusions.sorted(by: { $0.count > $1.count }) {
            guard let range = trimmed.range(of: marker, options: .backwards) else { continue }
            let conclusion = String(trimmed[range.lowerBound...])
                .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "。."))
            var parameters = String(trimmed[..<range.lowerBound])
                .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "。."))
            if parameters.hasSuffix("。") { parameters = String(parameters.dropLast()) }
            return (parameters, conclusion)
        }
        if let lastPeriod = trimmed.lastIndex(of: "。") {
            let tail = String(trimmed[trimmed.index(after: lastPeriod)...]).trimmingCharacters(in: CharacterSet.whitespaces)
            if tail.count >= 2, tail.count <= 24, tail.contains("心电图") || tail.contains("心律") {
                let head = String(trimmed[..<lastPeriod]).trimmingCharacters(in: CharacterSet.whitespaces)
                return (head, tail)
            }
        }
        return (trimmed, "")
    }

    static func isNormalECGConclusion(_ conclusion: String) -> Bool {
        let c = RiskAnalyzer.normalize(conclusion)
        // 不齐 / 过缓 / 过速 / 早搏等属异常心律，不可因含「窦性心律」子串判为正常
        if c.contains("不齐") || c.contains("过缓") || c.contains("过速")
            || c.contains("早搏") || c.contains("房颤") || c.contains("房扑") {
            return false
        }
        if c.contains("异常") && !c.contains("未见") { return false }
        if c.contains("正常") { return true }
        if c.contains("窦性心律") { return true }
        return false
    }

    static func extractTrailingConclusion(from text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: CharacterSet.whitespaces)
        for phrase in normalImagingPhrases.sorted(by: { $0.count > $1.count }) {
            if trimmed.contains(phrase) { return phrase }
        }
        if let lastPeriod = trimmed.lastIndex(of: "。") {
            let tail = String(trimmed[trimmed.index(after: lastPeriod)...]).trimmingCharacters(in: CharacterSet.whitespaces)
            if tail.count >= 4, tail.count <= 32 { return tail }
        }
        return nil
    }
}
