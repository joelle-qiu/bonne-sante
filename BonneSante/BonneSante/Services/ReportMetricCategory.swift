import Foundation

/// 体检报告指标归类（对齐常见三甲报告结构，如仁济）
/// @author jiali.qiu
enum ReportMetricCategory {

    struct SectionRule {
        let title: String
        let keywords: [String]
    }

    /// 展示顺序（与报告章节相近）
    static let orderedSections: [SectionRule] = [
        SectionRule(title: "基础数据", keywords: ["既往史", "身高", "体重", "体重指数", "bmi", "收缩压", "舒张压", "血压", "过敏史", "慢性病史", "传染病史", "吸烟史", "外伤史"]),
        SectionRule(title: "一般检查", keywords: ["发育", "营养", "面容", "皮肤黏膜", "胸廓", "呼吸音", "心律", "心音", "杂音", "腹部"]),
        SectionRule(title: "外科常规", keywords: ["甲状腺", "淋巴结", "乳腺", "肛门", "肛指", "四肢", "脊柱", "颈部肿块"]),
        SectionRule(title: "眼科常规", keywords: ["眼睑", "晶状体", "眼底"]),
        SectionRule(title: "五官科常规", keywords: ["咽喉", "耳", "鼻"]),
        SectionRule(title: "妇科常规", keywords: ["外阴", "阴道", "宫颈", "子宫", "附件", "宫颈糜烂"]),
        SectionRule(title: "血常规", keywords: [
            "白细胞", "红细胞", "血红蛋白", "血小板", "嗜", "中性", "淋巴", "单核", "有核红细胞",
            "红细胞压积", "平均红细胞", "血沉", "rdw", "mpv", "大血小板"
        ]),
        SectionRule(title: "凝血功能", keywords: [
            "凝血酶", "纤维蛋白", "二聚体", "国际标准化比值", "活化部分凝血"
        ]),
        SectionRule(title: "心脏标志物", keywords: [
            "肌钙蛋白", "肌酸激酶", "利钠肽", "肌红蛋白", "降钙素原"
        ]),
        SectionRule(title: "感染标志物", keywords: [
            "乙肝", "丙肝", "艾滋", "梅毒", "病毒抗体", "病毒核酸", "人类免疫缺陷"
        ]),
        SectionRule(title: "血液生化", keywords: [
            "胆红素", "转氨酶", "alt", "ast", "ggt", "谷氨", "碱性磷酸", "乳酸脱氢", "ldh",
            "尿素", "肌酐", "尿酸", "血糖", "egfr", "幽门", "总蛋白", "白蛋白", "球蛋白",
            "白球", "蛋白电泳", "胆碱", "胆甾醇"
        ]),
        SectionRule(title: "甲状腺功能", keywords: [
            "促甲状腺激素", "甲状腺素", "三碘甲状腺", "甲状腺球蛋白", "过氧化物酶抗体",
            "促甲状腺激素受体", "游离甲状腺"
        ]),
        SectionRule(title: "血脂", keywords: ["胆固醇", "甘油三酯", "脂蛋白", "hdl", "ldl"]),
        SectionRule(title: "尿常规", keywords: [
            "尿", "管型", "结晶", "粘液丝", "上皮细胞", "真菌", "尿比重", "尿蛋白", "尿潜血", "电导率"
        ]),
        SectionRule(title: "阴道分泌物", keywords: [
            "脓细胞", "清洁度", "滴虫", "霉菌", "线索细胞", "过氧化氢", "白细胞酯酶", "唾液酸苷酶"
        ]),
        SectionRule(title: "肿瘤标志物", keywords: ["癌胚", "甲胎", "ca19", "ca125", "糖类抗原", "cea", "afp"]),
        SectionRule(title: "心电图", keywords: ["心电图", "心率", "qt", "qrs", "pr间期", "电轴"]),
        SectionRule(title: "影像检查", keywords: [
            "结节", "肌瘤", "增生", "未见明显异常", "心肺", "甲状腺", "肝脏", "胆囊", "肾脏",
            "胰腺", "乳房", "胸片", "彩超", "b超"
        ])
    ]

    static let fallbackSection = "其他"

    /// DeepSeek / 粘贴 JSON 中的 section 字段归一化
    static func normalizeIncomingSection(_ raw: String?, metricName: String) -> String {
        let section = raw?.trimmingCharacters(in: .whitespaces) ?? ""
        let name = metricName.trimmingCharacters(in: .whitespaces)
        if section == "既往史" || section == "一般检查" || name.contains("既往史") || name.contains("身高体重") {
            return "基础数据"
        }
        if section == "检验" || section == "其他" { return "" }
        return section
    }

    /// 检验组合标题 → 报告章节
    static func sectionForPanel(_ panelName: String) -> String {
        let key = panelName.replacingOccurrences(of: " ", with: "").lowercased()
        if key.contains("全血细胞") || key.contains("血沉") || key.contains("血常规") { return "血常规" }
        if key.contains("血脂") { return "血脂" }
        if key.contains("肾") || key.contains("肝") || key.contains("血糖") || key.contains("尿素") || key.contains("幽门") {
            return "血液生化"
        }
        if key.contains("尿") { return "尿常规" }
        if key.contains("阴道") || key.contains("宫颈") || key.contains("涂片") { return "阴道分泌物" }
        if key.contains("肿瘤") || key.contains("抗原") || key.contains("胚抗原") || key.contains("甲胎") { return "肿瘤标志物" }
        if key.contains("既往") || key.contains("身高") || key.contains("体重") || key.contains("血压") { return "基础数据" }
        return ""
    }

    /// 检验组合 / 面板名 → 校对页与摘要中的专业展示名
    static func professionalPanelName(_ raw: String) -> String {
        let key = raw.replacingOccurrences(of: " ", with: "").lowercased()
        if key.isEmpty { return raw }

        let mapped: [(keywords: [String], label: String)] = [
            (["尿液分析组合", "尿液分析", "尿常规组合"], "尿常规"),
            (["血脂全套", "血脂组合"], "血脂"),
            (["全血细胞分析", "血细胞分析"], "血常规"),
            (["阴道分泌物常规组合", "阴道分泌物常规", "阴道分泌物"], "阴道分泌物检查"),
            (["身高体重血压", "身高体重"], "体格测量"),
            (["既往史"], "既往史"),
            (["肿瘤标志物"], "肿瘤标志物"),
            (["幽门螺旋杆菌抗体", "幽门螺杆菌抗体", "幽门螺旋杆菌"], "幽门螺杆菌（Hp）抗体"),
            (["子宫颈涂片", "宫颈涂片"], "宫颈细胞学检查"),
            (["空腹血糖"], "空腹血糖"),
            (["红细胞沉降率", "血沉"], "红细胞沉降率（ESR）"),
            (["肾功能"], "肾功能"),
            (["肝功能"], "肝功能")
        ]
        for entry in mapped where entry.keywords.contains(where: { key.contains($0.lowercased()) }) {
            return entry.label
        }

        let cleaned = raw
            .replacingOccurrences(of: "常规组合", with: "")
            .replacingOccurrences(of: "分析组合", with: "")
            .replacingOccurrences(of: "组合", with: "")
            .replacingOccurrences(of: "全套", with: "")
            .trimmingCharacters(in: .whitespaces)
        return cleaned.isEmpty ? raw : cleaned
    }

    /// 摘要展示用临床科目（妇科 / 内分泌科 / 泌尿科 等）
    static func clinicalDepartment(section: String, name: String, assessmentNote: String = "") -> String {
        let blob = RiskAnalyzer.normalize(section + name + assessmentNote)
        if blob.contains("宫颈") || blob.contains("阴道") || blob.contains("子宫") || blob.contains("附件") {
            return "妇科"
        }
        if blob.contains("纳氏") || blob.contains("纳囊") || blob.contains("腺囊肿") { return "妇科" }
        if section.contains("尿") || blob.contains("尿潜") || blob.contains("脓细胞") { return "泌尿科" }
        if section.contains("血脂") || blob.contains("胆固醇") || blob.contains("脂蛋白")
            || blob.contains("甘油三酯") || blob.contains("高脂") {
            return "内分泌科"
        }
        if section.contains("影像") || blob.contains("结节") || blob.contains("肌瘤")
            || blob.contains("彩超") || blob.contains("b超") || blob.contains("血管瘤")
            || blob.contains("低回声") || blob.contains("甲状腺") || blob.contains("乳腺") {
            return "影像科"
        }
        if blob.contains("颈椎") || blob.contains("曲度") || blob.contains("腰椎") { return "骨科康复" }
        if blob.contains("牙结石") || blob.contains("口腔") { return "口腔科" }
        if blob.contains("心律") || blob.contains("心电图") || blob.contains("窦性") { return "心血管科" }
        if section.contains("肝") || section.contains("胆") || blob.contains("转氨酶") { return "消化内科" }
        if section.contains("血常规") { return "检验科" }
        if section.contains("肿瘤") { return "肿瘤科" }
        if section.contains("甲状腺") { return "内分泌科" }
        if !section.isEmpty, section != fallbackSection { return section }
        return "其他"
    }

    /// 根据指标名称推断报告章节
    static func inferSection(name: String, valueText: String = "") -> String {
        let key = (name + valueText)
            .replacingOccurrences(of: " ", with: "")
            .lowercased()
        for rule in orderedSections {
            if rule.keywords.contains(where: { key.contains($0.lowercased()) }) {
                return rule.title
            }
        }
        return fallbackSection
    }

    /// 异常发现 category → 报告章节
    static func sectionForFinding(category: String) -> String {
        switch category.trimmingCharacters(in: .whitespaces) {
        case "影像": return "影像检查"
        case "妇科": return "妇科常规"
        case "外科": return "外科常规"
        case "心电图": return "心电图"
        case "检验": return "血液生化"
        default: return category.isEmpty ? "异常发现" : category
        }
    }

    /// 为 DraftMetric 自动补全 section
    static func assignSection(to metric: inout ReportImporter.DraftMetric) {
        if !metric.section.isEmpty, metric.section != fallbackSection { return }
        metric.section = inferSection(name: metric.name, valueText: metric.valueText)
    }

    static func assignSections(to metrics: inout [ReportImporter.DraftMetric]) {
        for index in metrics.indices {
            assignSection(to: &metrics[index])
        }
    }

    /// 按章节分组并保持报告顺序
    static func grouped<T>(
        _ items: [T],
        section: (T) -> String
    ) -> [(title: String, items: [T])] {
        var buckets: [String: [T]] = [:]
        for item in items {
            let key = section(item)
            buckets[key, default: []].append(item)
        }
        var order = orderedSections.map(\.title) + [fallbackSection, "异常发现"]
        for key in buckets.keys where !order.contains(key) {
            order.append(key)
        }
        return order.compactMap { title in
            guard let list = buckets[title], !list.isEmpty else { return nil }
            return (title, list)
        }
    }
}
