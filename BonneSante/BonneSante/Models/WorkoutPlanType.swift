import Foundation

/// 周训练计划类型（三分化 / 部位专项 / 有氧等）
/// @author jiali.qiu
enum WorkoutPlanType: String, CaseIterable, Identifiable, Codable {
    case balanced
    case threeDaySplit
    case threeDaySplitPlusCardio
    case glutesLegs
    case shouldersBack
    case cardioFocus
    /// 健身房场地 · 舞蹈（不拆具体动作，侧重时长与消耗）
    case dance
    /// 健身房场地 · 游泳（默认蛙泳距离与时长）
    case swimming

    /// 计划大类（UI 分组）
    enum Category: String {
        case gymStrength = "健身房 · 力量"
        case gymFacility = "健身房 · 场地"
    }

    var category: Category {
        switch self {
        case .dance, .swimming: return .gymFacility
        default: return .gymStrength
        }
    }

    static var gymStrengthTypes: [WorkoutPlanType] {
        allCases.filter { $0.category == .gymStrength }
    }

    static var gymFacilityTypes: [WorkoutPlanType] {
        [.dance, .swimming]
    }

    /// 是否依赖天气推荐晚间排课
    var usesWeatherScheduling: Bool {
        category == .gymFacility
    }

    /// 是否简化动作清单（舞蹈/游泳）
    var usesSimplifiedSessionFormat: Bool {
        category == .gymFacility
    }

    var id: String { rawValue }

    /// 三分化标准四日循环（肩背 → 臀腿 → 核心有氧 → 全身）
    static let threeDaySplitCycle: [String] = [
        "三分化·肩背",
        "三分化·臀腿",
        "三分化·核心有氧",
        "全身训练"
    ]

    var label: String {
        switch self {
        case .balanced: return "智能均衡"
        case .threeDaySplit: return "三分化"
        case .threeDaySplitPlusCardio: return "三分化（完整）"
        case .glutesLegs: return "臀腿专项"
        case .shouldersBack: return "肩背专项"
        case .cardioFocus: return "有氧为主"
        case .dance: return "舞蹈"
        case .swimming: return "游泳"
        }
    }

    var subtitle: String {
        switch self {
        case .balanced: return "按周期自动搭配力量与有氧"
        case .threeDaySplit: return "肩背 · 臀腿 · 核心有氧"
        case .threeDaySplitPlusCardio: return "肩背 · 臀腿 · 核心有氧 · 全身"
        case .glutesLegs: return "深蹲、硬拉、臀桥为主"
        case .shouldersBack: return "划船、下拉、肩推为主"
        case .cardioFocus: return "跑走骑 HIIT，辅助减脂"
        case .dance: return "舞室/团课 · 结合天气排晚间"
        case .swimming: return "泳池 · 默认蛙泳计划"
        }
    }

    var systemImage: String {
        switch self {
        case .balanced: return "sparkles"
        case .threeDaySplit, .threeDaySplitPlusCardio: return "square.grid.3x1.fill"
        case .glutesLegs: return "figure.strengthtraining.functional"
        case .shouldersBack: return "figure.arms.open"
        case .cardioFocus: return "figure.run"
        case .dance: return "figure.dance"
        case .swimming: return "figure.pool.swim"
        }
    }

    var recommendedSessionsPerWeek: Int {
        switch self {
        case .balanced: return 4
        case .threeDaySplit: return 3
        case .threeDaySplitPlusCardio: return 4
        case .glutesLegs: return 3
        case .shouldersBack: return 3
        case .cardioFocus: return 4
        case .dance: return 2
        case .swimming: return 2
        }
    }

    var aiInstruction: String {
        switch self {
        case .balanced:
            return "计划类型：智能均衡。按周期阶段搭配力量、HIIT 与有氧，兼顾消耗与恢复。"
        case .threeDaySplit:
            return """
            计划类型：三分化（3 练/周）。
            按训练日循环：①肩背（背、肩）②臀腿（臀、腿）③核心和有氧（核心激活 + 有氧消耗）。
            workoutType 请写「三分化·肩背」「三分化·臀腿」「三分化·核心有氧」；禁止使用「推力/拉力/PPL」等称谓。
            """
        case .threeDaySplitPlusCardio:
            return """
            计划类型：三分化完整版（4 练/周）。
            按训练日循环：①肩背 ②臀腿 ③核心和有氧 ④全身训练（复合动作为主）。
            workoutType 请写「三分化·肩背」「三分化·臀腿」「三分化·核心有氧」「全身训练」。
            """
        case .glutesLegs:
            return """
            计划类型：臀腿专项。
            力量日以臀、腿为主（深蹲、硬拉、臀推、弓步、臀桥等）；可穿插 1 场低冲击有氧恢复。
            workoutType 请写「臀腿专项」；muscleGroup 侧重腿、臀。
            """
        case .shouldersBack:
            return """
            计划类型：肩背专项。
            力量日以背、肩为主（划船、下拉、面拉、推举、侧平举等）；可穿插 1 场有氧。
            workoutType 请写「肩背专项」；muscleGroup 侧重背、肩。
            """
        case .cardioFocus:
            return """
            计划类型：有氧为主。
            至少 70% 训练日为有氧/HIIT（跑、走、骑、椭圆、HIIT）；力量仅 0–1 场轻量维持。
            workoutType 优先跑步、快走、HIIT、骑行、椭圆机等。
            """
        case .dance:
            return """
            计划类型：健身房 · 舞蹈（场地项目）。
            - 不要像力量训练一样拆 4+ 个器械动作；exercises 仅 1 条汇总（如「舞蹈团课」）。
            - 重点：workoutType=「舞蹈」、targetMinutes（45–75）、targetCalories、notes（含建议 19:00 开始及天气理由）。
            - 结合【本地一周天气】，优先把工作日晚间（周一–周五）且 19:00 左右天气适宜的日期排课。
            """
        case .swimming:
            return """
            计划类型：健身房 · 游泳（场地项目）。
            - workoutType=「游泳」；默认泳姿蛙泳。
            - exercises 仅 1 条：name=「蛙泳」、reps 写距离如「800米」、sets=1、exerciseKind=cardio。
            - notes 含总时长、分段（热身/主项/放松）及 19:00 左右开始时间与天气说明。
            - 结合【本地一周天气】优先工作日晚间排课。
            """
        }
    }
}

/// 训练计划风格：专业（自选类型） / 心情（按天气舞蹈↔游泳）
/// @author jiali.qiu
enum WorkoutPlanStyle: String, Codable, CaseIterable, Identifiable {
    case professional
    case moodWeather

    var id: String { rawValue }

    var label: String {
        switch self {
        case .professional: return "专业"
        case .moodWeather: return "心情"
        }
    }

    var subtitle: String {
        switch self {
        case .professional: return "自选力量/舞蹈/游泳等类型"
        case .moodWeather: return "下雨游泳 · 晴天跳舞"
        }
    }

    var systemImage: String {
        switch self {
        case .professional: return "figure.strengthtraining.traditional"
        case .moodWeather: return "cloud.sun.rain.fill"
        }
    }

    /// 是否需要拉取天气
    var usesWeather: Bool {
        self == .moodWeather
    }
}

/// 心情模式文案与备物提示
enum MoodWorkoutTips {
    static let swimmingPackingList = "泳衣、泳帽、泳镜、浴巾、拖鞋、换洗衣物、防水袋"

    static func swimmingSessionNote(weekdayLabel: String, weatherSummary: String?, isStorm: Bool = false) -> String {
        var parts = ["\(weekdayLabel) 19:00"]
        if let weatherSummary, !weatherSummary.isEmpty {
            parts.append(weatherSummary)
        }
        if isStorm {
            parts.append("雷暴日请选室内泳池，注意安全")
        }
        parts.append("下雨和游泳更搭")
        parts.append("携带：\(swimmingPackingList)")
        return parts.joined(separator: " · ")
    }

    static func danceSessionNote(weekdayLabel: String, weatherSummary: String?) -> String {
        var parts = ["\(weekdayLabel) 19:00"]
        if let weatherSummary, !weatherSummary.isEmpty {
            parts.append(weatherSummary)
        }
        parts.append("天气不错，去跳舞吧")
        return parts.joined(separator: " · ")
    }

    /// 规则引擎用：从本地池随机挑 1 句温馨提醒（每次生成不同组合）
    static func randomReminder(for activity: WorkoutPlanType, nickname: String? = nil) -> String {
        let swimmingReminders = [
            "别忘带泳帽哦～",
            "浴巾和拖鞋也记得塞进包里～",
            "泳镜擦亮点，看得更清楚呀～",
            "换洗衣物别落下，游完一身轻松～",
            "防水袋装好湿泳衣，回家省心～",
            "下水前先热身五分钟，膝盖会感谢你～",
            "雷暴天记得选室内池，安全第一～"
        ]
        let danceReminders = [
            "穿双舒服的运动鞋，跳得更带感～",
            "带个小水壶，中场补水很重要～",
            "扎好头发，跳舞的时候更利落～",
            "热身五分钟，晚高峰也不慌～",
            "穿透气衣服，出汗也自在～",
            "今晚去好好跳一场，把烦恼甩在舞室门外～",
            "记得带条小毛巾擦汗哦～"
        ]
        let pool = activity == .swimming ? swimmingReminders : danceReminders
        let message = pool.randomElement() ?? pool[0]
        let trimmedNick = nickname?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if trimmedNick.isEmpty { return message }
        return "\(trimmedNick)，\(message)"
    }
}

/// 单场训练可切换的侧重（不限于当前周计划类型）
/// @author jiali.qiu
enum WorkoutSessionFocus: String, CaseIterable, Identifiable {
    case shouldersBack
    case glutesLegs
    case coreCardio
    case fullBody
    case cardio
    case hiit

    var id: String { rawValue }

    var label: String {
        switch self {
        case .shouldersBack: return "肩背"
        case .glutesLegs: return "臀腿"
        case .coreCardio: return "核心和有氧"
        case .fullBody: return "全身训练"
        case .cardio: return "有氧"
        case .hiit: return "HIIT"
        }
    }

    var displayWorkoutType: String {
        switch self {
        case .shouldersBack: return "肩背训练"
        case .glutesLegs: return "臀腿训练"
        case .coreCardio: return "核心和有氧"
        case .fullBody: return "全身训练"
        case .cardio: return "有氧训练"
        case .hiit: return "HIIT"
        }
    }

    var engineWorkoutType: String {
        switch self {
        case .shouldersBack: return "三分化·肩背"
        case .glutesLegs: return "三分化·臀腿"
        case .coreCardio: return "三分化·核心有氧"
        case .fullBody: return "全身训练"
        case .cardio: return "快走"
        case .hiit: return "HIIT"
        }
    }
}