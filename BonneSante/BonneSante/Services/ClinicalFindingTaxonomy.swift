import Foundation

/// 临床发现形态 / 部位标准化标签（由 DeepSeek 标注，App 动态归类）
/// @author jiali.qiu
enum ClinicalFindingTaxonomy {

    /// 形态 / 性质（封闭枚举，DeepSeek 必须从中选取主标签）
    enum Morphology: String, CaseIterable, Sendable {
        case cyst = "cyst"
        case nodule = "nodule"
        case tumor = "tumor"
        case hemangioma = "hemangioma"
        case hyperplasia = "hyperplasia"
        case fibroid = "fibroid"
        case stone = "stone"
        case arrhythmia = "arrhythmia"
        case structural = "structural"
        case infection = "infection"
        case erosion = "erosion"
        case calcification = "calcification"
        case lipid = "lipid"
        case echoAbnormal = "echo_abnormal"
        case normal = "normal"
        case other = "other"

        var displayLabel: String {
            switch self {
            case .cyst: return "囊肿"
            case .nodule: return "结节"
            case .tumor: return "肿瘤"
            case .hemangioma: return "血管瘤"
            case .hyperplasia: return "增生"
            case .fibroid: return "肌瘤"
            case .stone: return "结石"
            case .arrhythmia: return "心律异常"
            case .structural: return "结构改变"
            case .infection: return "感染"
            case .erosion: return "糜烂样改变"
            case .calcification: return "钙化"
            case .lipid: return "血脂异常"
            case .echoAbnormal: return "回声异常"
            case .normal: return "未见异常"
            case .other: return "其他发现"
            }
        }

        var isClinicallySignificant: Bool {
            self != .normal && self != .other
        }
    }

    /// 器官 / 部位（封闭枚举）
    enum OrganSite: String, CaseIterable, Sendable {
        case liver = "liver"
        case thyroid = "thyroid"
        case breast = "breast"
        case uterus = "uterus"
        case cervix = "cervix"
        case ovary = "ovary"
        case spine = "spine"
        case heart = "heart"
        case kidney = "kidney"
        case lung = "lung"
        case gallbladder = "gallbladder"
        case pancreas = "pancreas"
        case dental = "dental"
        case bladder = "bladder"
        case prostate = "prostate"
        case eye = "eye"
        case skin = "skin"
        case blood = "blood"
        case other = "other"

        var displayLabel: String {
            switch self {
            case .liver: return "肝脏"
            case .thyroid: return "甲状腺"
            case .breast: return "乳腺"
            case .uterus: return "子宫"
            case .cervix: return "子宫颈"
            case .ovary: return "卵巢"
            case .spine: return "脊柱"
            case .heart: return "心脏"
            case .kidney: return "肾脏"
            case .lung: return "肺部"
            case .gallbladder: return "胆囊"
            case .pancreas: return "胰腺"
            case .dental: return "口腔"
            case .bladder: return "膀胱"
            case .prostate: return "前列腺"
            case .eye: return "眼"
            case .skin: return "皮肤"
            case .blood: return "血液"
            case .other: return "其他"
            }
        }
    }

    struct Tags: Sendable, Equatable {
        var morphology: Morphology
        var organSite: OrganSite
        var extraMorphology: [Morphology]

        static let empty = Tags(morphology: .other, organSite: .other, extraMorphology: [])

        var isEmpty: Bool {
            morphology == .other && organSite == .other && extraMorphology.isEmpty
        }

        /// 摘要展示用简短描述（优先 AI 标签，避免硬编码术语表）
        var briefLabel: String {
            if morphology == .nodule, organSite == .lung { return "肺部结节（磨玻璃）" }
            if morphology == .hemangioma, organSite == .liver { return "肝血管瘤/FNH" }
            if morphology == .fibroid, organSite == .uterus { return "子宫肌瘤" }
            let morph = morphology.displayLabel
            let organ = organSite.displayLabel
            if morphology == .other, organSite == .other { return "" }
            if morphology == .other { return organ }
            if organSite == .other { return morph }
            return "\(organ)\(morph)"
        }
    }

    // MARK: - 解析

    static func normalizeMorphology(_ raw: String?) -> Morphology {
        let key = RiskAnalyzer.normalize(raw ?? "")
        if key.isEmpty { return .other }
        for item in Morphology.allCases where key == item.rawValue || key.contains(item.rawValue) {
            return item
        }
        let aliases: [(String, Morphology)] = [
            ("囊肿", .cyst), ("纳氏", .cyst), ("纳囊", .cyst), ("腺囊肿", .cyst),
            ("结节", .nodule), ("占位", .nodule), ("磨玻璃", .nodule),
            ("肿瘤", .tumor), ("癌", .tumor), ("恶性", .tumor),
            ("血管瘤", .hemangioma), ("低回声", .hemangioma),
            ("增生", .hyperplasia),
            ("肌瘤", .fibroid),
            ("结石", .stone), ("牙结石", .stone),
            ("心律", .arrhythmia), ("不齐", .arrhythmia), ("窦性", .arrhythmia),
            ("曲度", .structural), ("变直", .structural), ("退变", .structural),
            ("感染", .infection), ("炎症", .infection), ("阳性", .infection),
            ("糜烂", .erosion),
            ("钙化", .calcification),
            ("胆固醇", .lipid), ("血脂", .lipid), ("脂蛋白", .lipid),
            ("回声", .echoAbnormal), ("欠均匀", .echoAbnormal),
            ("正常", .normal), ("未见", .normal), ("阴性", .normal)
        ]
        for (alias, morph) in aliases where key.contains(RiskAnalyzer.normalize(alias)) {
            return morph
        }
        return .other
    }

    static func normalizeOrganSite(_ raw: String?) -> OrganSite {
        let key = RiskAnalyzer.normalize(raw ?? "")
        if key.isEmpty { return .other }
        for item in OrganSite.allCases where key == item.rawValue || key.contains(item.rawValue) {
            return item
        }
        let aliases: [(String, OrganSite)] = [
            ("肝", .liver), ("甲状腺", .thyroid), ("乳腺", .breast), ("乳房", .breast),
            ("子宫", .uterus), ("宫颈", .cervix), ("子宫颈", .cervix), ("附件", .ovary),
            ("卵巢", .ovary), ("颈椎", .spine), ("腰椎", .spine), ("脊柱", .spine),
            ("心", .heart), ("肾", .kidney), ("肺", .lung), ("胆", .gallbladder),
            ("胰", .pancreas), ("牙", .dental), ("口腔", .dental),
            ("膀胱", .bladder), ("前列腺", .prostate)
        ]
        for (alias, organ) in aliases where key.contains(RiskAnalyzer.normalize(alias)) {
            return organ
        }
        return .other
    }

    static func parseTags(
        morphology: String?,
        organSite: String?,
        morphologyTags: [String]? = nil
    ) -> Tags {
        let primary = normalizeMorphology(morphology)
        let organ = normalizeOrganSite(organSite)
        let extras = (morphologyTags ?? [])
            .map { normalizeMorphology($0) }
            .filter { $0 != .other && $0 != primary }
        return Tags(morphology: primary, organSite: organ, extraMorphology: extras)
    }

    /// 无 AI 标签时，从标题 / 详情 / 结论推断（兜底）
    static func inferFromText(_ text: String) -> Tags {
        Tags(
            morphology: normalizeMorphology(text),
            organSite: normalizeOrganSite(text),
            extraMorphology: []
        )
    }

    /// 摘要用临床科室（优先 AI 标签，其次原文关键词）
    static func clinicalDepartment(
        tags: Tags,
        section: String = "",
        name: String = "",
        assessmentNote: String = ""
    ) -> String {
        if tags.organSite == .cervix || tags.organSite == .uterus || tags.organSite == .ovary {
            return "妇科"
        }
        if tags.organSite == .spine { return "骨科康复" }
        if tags.organSite == .dental { return "口腔科" }
        if tags.organSite == .heart || tags.morphology == .arrhythmia { return "心血管科" }
        if tags.organSite == .lung {
            return (tags.morphology == .nodule || tags.morphology == .tumor) ? "胸外科" : "影像科"
        }
        if tags.organSite == .liver, tags.morphology == .hemangioma { return "肝胆外科" }
        if tags.organSite == .bladder { return "泌尿科" }
        if tags.morphology == .lipid || tags.organSite == .blood { return "内分泌科" }
        if tags.organSite == .liver || tags.organSite == .thyroid || tags.organSite == .breast
            || tags.organSite == .lung || tags.organSite == .kidney {
            return "影像科"
        }
        return ReportMetricCategory.clinicalDepartment(
            section: section,
            name: name,
            assessmentNote: assessmentNote
        )
    }

    static func isClinicallySignificant(tags: Tags, isAbnormal: Bool, severityRank: Int) -> Bool {
        if tags.morphology == .normal { return false }
        if tags.morphology.isClinicallySignificant || !tags.extraMorphology.isEmpty {
            return true
        }
        if tags.organSite != .other, isAbnormal || severityRank > 0 {
            return true
        }
        return isAbnormal
    }

    static func encodeTags(_ tags: Tags) -> (morphology: String, organSite: String) {
        (tags.morphology.rawValue, tags.organSite.rawValue)
    }

    static func decodeStored(morphologyTag: String, organSiteTag: String) -> Tags {
        parseTags(morphology: morphologyTag, organSite: organSiteTag)
    }
}
