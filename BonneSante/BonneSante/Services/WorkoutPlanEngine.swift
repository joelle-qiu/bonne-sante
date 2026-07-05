import Foundation

/// 按周期阶段 + 减脂目标 + 运动历史生成结构化周训练计划（纯函数）
/// @author jiali.qiu
enum WorkoutPlanEngine {

    struct Input {
        var phase: CyclePhase
        var cycleDay: Int
        var sessionsPerWeek: Int
        var currentWeight: Double?
        var targetWeight: Double?
        var activityLevel: String
        var dailyCalorieBudget: Double?
        var proteinTargetGrams: Double?
        var recentWorkoutMinutes7d: Int
        var recentWorkoutCount7d: Int
        var healthDietNotes: [String]
        var riskHints: [String]
        var cycleWorkoutTip: String
        /// 每日热量缺口目标（kcal）
        var dailyDeficitTarget: Double?
        /// 计划类型（三分化 / 部位专项等）
        var planType: WorkoutPlanType
        /// 专业 / 心情（按天气舞蹈↔游泳）
        var planStyle: WorkoutPlanStyle
        /// 心情模式用户覆盖 weekday → 活动
        var moodDayOverrides: [Int: WorkoutPlanType]
        /// 心情模式用户固定排课 weekday（nil 则自动选最优组合）
        var moodPinnedWeekdays: [Int]?
        /// 用户称呼（心情提醒个性化，如「小姜」）
        var profileNickname: String
    }

    struct PlannedExercise: Equatable {
        var name: String
        var muscleGroup: String
        var equipment: String
        var sets: Int
        var reps: String
        var restSeconds: Int
        var targetCalories: Double
        var notes: String
        var exerciseKind: String
    }

    struct PlannedSession: Equatable {
        var dayOfWeek: Int
        var workoutType: String
        var targetMinutes: Int
        var intensity: String
        var notes: String
        /// 心情模式口语提醒（详情页展示，与 notes 分工）
        var moodReminder: String
        var targetCalories: Double
        var exercises: [PlannedExercise]
    }

    struct Output: Equatable {
        var sessions: [PlannedSession]
        var weeklyModerateMinutesGoal: Int
        var strengthSessionsGoal: Int
        var dietAdvice: String
        var weeklySummary: String
        /// 本周训练消耗总目标（优先服务于减脂缺口）
        var weeklyBurnGoalKcal: Double
        /// 每日营养摄入目标（训练日 + 休息日）
        var splitNutrition: WorkoutNutritionPlanner.SplitNutritionPlan
    }

    /// 生成规则版周计划
    static func calculate(_ input: Input, weather: WeeklyWeatherSnapshot? = nil) -> Output {
        if input.planStyle == .moodWeather {
            return calculateMoodPlan(input, weather: weather)
        }
        let sessionsCount = min(max(input.sessionsPerWeek, 2), 6)
        let slots = input.planType.usesWeatherScheduling
            ? facilityWeekdaySlots(for: sessionsCount)
            : weekdaySlots(for: sessionsCount)
        let templates = sessionTemplates(
            for: input.phase,
            count: sessionsCount,
            activityLevel: input.activityLevel,
            planType: input.planType
        )
        let sessions = zip(slots, templates.enumerated()).map { day, indexed in
            let (index, template) = indexed
            var exercises = exercisesForTemplate(
                template,
                phase: input.phase,
                planType: input.planType,
                sessionIndex: index
            )
            var calories = exercises.reduce(0) { $0 + $1.targetCalories }
            let perSessionBurn = targetBurnPerSession(input: input, sessionsCount: sessionsCount)
            if calories < perSessionBurn * 0.85, !exercises.isEmpty {
                exercises = scaleExerciseCalories(exercises, toTotal: perSessionBurn)
                calories = perSessionBurn
            }
            return PlannedSession(
                dayOfWeek: day,
                workoutType: template.type,
                targetMinutes: template.minutes,
                intensity: template.intensity,
                notes: template.note,
                moodReminder: "",
                targetCalories: calories > 0 ? calories : estimatedSessionCalories(minutes: template.minutes, intensity: template.intensity),
                exercises: exercises
            )
        }

        let weeklyBurn = sessions.reduce(0) { $0 + $1.targetCalories }

        let moderateGoal = moderateMinutesGoal(phase: input.phase, sessions: sessionsCount, activityLevel: input.activityLevel)
        let strengthGoal = strengthSessionsGoal(phase: input.phase, sessions: sessions)

        let splitNutrition = WorkoutNutritionPlanner.fromEngineSplit(
            dailyBudget: input.dailyCalorieBudget,
            proteinGrams: input.proteinTargetGrams,
            carbGrams: nil,
            fatGrams: nil,
            phase: input.phase
        )

        return Output(
            sessions: sessions,
            weeklyModerateMinutesGoal: moderateGoal,
            strengthSessionsGoal: strengthGoal,
            dietAdvice: buildDietAdvice(input: input, split: splitNutrition),
            weeklySummary: buildWeeklySummary(
                input: input,
                sessions: sessions,
                moderateGoal: moderateGoal,
                strengthGoal: strengthGoal,
                weeklyBurn: weeklyBurn,
                planType: input.planType
            ),
            weeklyBurnGoalKcal: weeklyBurn,
            splitNutrition: splitNutrition
        )
    }

    /// 心情模式：按每日 19:00 天气在舞蹈 / 游泳间切换
    private static func calculateMoodPlan(_ input: Input, weather: WeeklyWeatherSnapshot?) -> Output {
        let sessionsCount = min(max(input.sessionsPerWeek, 2), 6)
        let planned = MoodWorkoutScheduler.schedule(
            sessionsCount: sessionsCount,
            weather: weather,
            overrides: input.moodDayOverrides,
            pinnedWeekdays: input.moodPinnedWeekdays
        )
        let boost = activityBoost(input.activityLevel)
        var danceIndex = 0
        var swimIndex = 0

        let sessions = planned.map { slot -> PlannedSession in
            let activity = slot.activity
            let isSwim = activity == .swimming
            let templates = isSwim
                ? swimmingTemplates(count: sessionsCount, boost: boost, phase: input.phase)
                : danceTemplates(count: sessionsCount, boost: boost, phase: input.phase)
            let templateIndex = isSwim ? swimIndex : danceIndex
            if isSwim { swimIndex += 1 } else { danceIndex += 1 }
            let template = templates[templateIndex % max(templates.count, 1)]

            let forecast = weather?.day(forWeekday: slot.dayOfWeek)
            let note = isSwim
                ? MoodWorkoutTips.swimmingSessionNote(
                    weekdayLabel: slot.weekdayLabel,
                    weatherSummary: slot.weatherSummary,
                    isStorm: forecast?.isStormyEvening ?? false
                )
                : MoodWorkoutTips.danceSessionNote(weekdayLabel: slot.weekdayLabel, weatherSummary: slot.weatherSummary)

            var exercises = exercisesForTemplate(
                SessionTemplate(type: template.type, minutes: template.minutes, intensity: template.intensity, note: note),
                phase: input.phase,
                planType: activity,
                sessionIndex: templateIndex
            )
            var calories = exercises.reduce(0) { $0 + $1.targetCalories }
            let perSessionBurn = targetBurnPerSession(input: input, sessionsCount: sessionsCount)
            if calories < perSessionBurn * 0.85, !exercises.isEmpty {
                exercises = scaleExerciseCalories(exercises, toTotal: perSessionBurn)
                calories = perSessionBurn
            }

            return PlannedSession(
                dayOfWeek: slot.dayOfWeek,
                workoutType: template.type,
                targetMinutes: template.minutes,
                intensity: template.intensity,
                notes: note,
                moodReminder: MoodWorkoutTips.randomReminder(
                    for: activity,
                    nickname: input.profileNickname.isEmpty ? nil : input.profileNickname
                ),
                targetCalories: calories > 0 ? calories : estimatedSessionCalories(minutes: template.minutes, intensity: template.intensity),
                exercises: exercises
            )
        }

        let swimCount = planned.filter { $0.activity == .swimming }.count
        let danceCount = planned.count - swimCount
        let weeklyBurn = sessions.reduce(0) { $0 + $1.targetCalories }
        let moderateGoal = moderateMinutesGoal(phase: input.phase, sessions: sessionsCount, activityLevel: input.activityLevel)
        let strengthGoal = 0
        let splitNutrition = WorkoutNutritionPlanner.fromEngineSplit(
            dailyBudget: input.dailyCalorieBudget,
            proteinGrams: input.proteinTargetGrams,
            carbGrams: nil,
            fatGrams: nil,
            phase: input.phase
        )

        var summary = buildWeeklySummary(
            input: input,
            sessions: sessions,
            moderateGoal: moderateGoal,
            strengthGoal: strengthGoal,
            weeklyBurn: weeklyBurn,
            planType: .dance
        )
        summary = "心情模式 · 游泳 \(swimCount) 场 · 舞蹈 \(danceCount) 场 · " + summary + " · 下雨游泳、晴天跳舞"

        return Output(
            sessions: sessions,
            weeklyModerateMinutesGoal: moderateGoal,
            strengthSessionsGoal: strengthGoal,
            dietAdvice: buildDietAdvice(input: input, split: splitNutrition),
            weeklySummary: summary,
            weeklyBurnGoalKcal: weeklyBurn,
            splitNutrition: splitNutrition
        )
    }

    /// 每场训练消耗目标：优先满足减脂热量缺口（约每日缺口 35% 由训练承担，均摊到各训练日）
    static func targetBurnPerSession(input: Input, sessionsCount: Int) -> Double {
        if let deficit = input.dailyDeficitTarget, deficit > 0 {
            return deficit * 0.35
        }
        if let budget = input.dailyCalorieBudget, budget > 0 {
            return budget * 0.12
        }
        return 220
    }

    private static func scaleExerciseCalories(
        _ exercises: [PlannedExercise],
        toTotal target: Double
    ) -> [PlannedExercise] {
        let current = exercises.reduce(0) { $0 + $1.targetCalories }
        guard current > 0 else { return exercises }
        let factor = target / current
        return exercises.map { ex in
            var copy = ex
            copy.targetCalories = max(ex.targetCalories * factor, 15)
            return copy
        }
    }

    /// 按训练类型生成具体动作清单
    static func exercisesForTemplate(
        _ template: SessionTemplate,
        phase: CyclePhase,
        planType: WorkoutPlanType = .balanced,
        sessionIndex: Int = 0
    ) -> [PlannedExercise] {
        let type = template.type
        if type.contains("三分化·") || type.contains("全身训练") || type.contains("臀腿专项") || type.contains("肩背专项") {
            return strengthExercises(for: type, phase: phase)
        }
        if type.contains("力量") {
            return strengthExercises(for: planType, phase: phase, sessionIndex: sessionIndex)
        }
        if type.contains("HIIT") {
            return [
                PlannedExercise(name: "开合跳", muscleGroup: "全身", equipment: "自重", sets: 4, reps: "40秒", restSeconds: 20, targetCalories: 35, notes: "热身", exerciseKind: "cardio"),
                PlannedExercise(name: "波比跳", muscleGroup: "全身", equipment: "自重", sets: 3, reps: "10", restSeconds: 45, targetCalories: 55, notes: "核心收紧", exerciseKind: "cardio"),
                PlannedExercise(name: "高抬腿", muscleGroup: "下肢", equipment: "自重", sets: 3, reps: "30秒", restSeconds: 30, targetCalories: 30, notes: "", exerciseKind: "cardio")
            ]
        }
        if type.contains("瑜伽") || type.contains("普拉提") {
            return [
                PlannedExercise(name: "猫牛式", muscleGroup: "核心", equipment: "瑜伽垫", sets: 2, reps: "10次", restSeconds: 15, targetCalories: 15, notes: "脊柱活动", exerciseKind: "mobility"),
                PlannedExercise(name: "下犬式", muscleGroup: "全身", equipment: "瑜伽垫", sets: 3, reps: "30秒", restSeconds: 20, targetCalories: 20, notes: "", exerciseKind: "mobility"),
                PlannedExercise(name: "臀桥", muscleGroup: "臀", equipment: "瑜伽垫", sets: 3, reps: "15", restSeconds: 30, targetCalories: 25, notes: "", exerciseKind: "strength")
            ]
        }
        if type.contains("舞蹈") {
            return danceSessionExercises(minutes: template.minutes, calories: Double(template.minutes * 6))
        }
        if type.contains("游泳") {
            return swimmingSessionExercises(minutes: template.minutes, calories: Double(template.minutes * 7))
        }
        if type.contains("跑") || type.contains("走") || type.contains("骑") {
            return [
                PlannedExercise(name: type, muscleGroup: "有氧", equipment: "—", sets: 1, reps: "\(template.minutes)分钟", restSeconds: 0, targetCalories: Double(template.minutes) * 6, notes: template.note, exerciseKind: "cardio")
            ]
        }
        return [
            PlannedExercise(name: "动态热身", muscleGroup: "全身", equipment: "自重", sets: 1, reps: "5分钟", restSeconds: 0, targetCalories: 25, notes: "", exerciseKind: "mobility"),
            PlannedExercise(name: type, muscleGroup: "有氧", equipment: "—", sets: 1, reps: "\(max(template.minutes - 10, 15))分钟", restSeconds: 0, targetCalories: Double(template.minutes) * 5, notes: template.note, exerciseKind: "cardio")
        ]
    }

    private static func strengthExercises(
        for workoutType: String,
        phase: CyclePhase
    ) -> [PlannedExercise] {
        // 新三分化命名
        if workoutType.contains("肩背") {
            return shouldersBackExercises(phase: phase)
        }
        if workoutType.contains("臀腿") && workoutType.contains("三分化") {
            return glutesLegsExercises(phase: phase)
        }
        if workoutType.contains("核心有氧") {
            return coreCardioExercises(phase: phase)
        }
        if workoutType.contains("全身训练") {
            return fullBodyExercises(phase: phase)
        }
        // 旧计划兼容（重新生成后将不再出现）
        if workoutType.contains("推力") {
            return shouldersBackExercises(phase: phase)
        }
        if workoutType.contains("拉力") {
            return shouldersBackExercises(phase: phase)
        }
        if workoutType.contains("臀腿专项") {
            return glutesLegsExercises(phase: phase)
        }
        if workoutType.contains("肩背专项") {
            return shouldersBackExercises(phase: phase)
        }
        return strengthExerciseBlock(phase: phase)
    }

    private static func strengthExercises(
        for planType: WorkoutPlanType,
        phase: CyclePhase,
        sessionIndex: Int
    ) -> [PlannedExercise] {
        switch planType {
        case .threeDaySplit:
            let cycle = Array(WorkoutPlanType.threeDaySplitCycle.prefix(3))
            let label = cycle[sessionIndex % cycle.count]
            return strengthExercises(for: label, phase: phase)
        case .threeDaySplitPlusCardio:
            let label = WorkoutPlanType.threeDaySplitCycle[sessionIndex % WorkoutPlanType.threeDaySplitCycle.count]
            return strengthExercises(for: label, phase: phase)
        case .glutesLegs:
            return glutesLegsExercises(phase: phase)
        case .shouldersBack:
            return shouldersBackExercises(phase: phase)
        case .balanced, .cardioFocus:
            return strengthExerciseBlock(phase: phase)
        case .dance, .swimming:
            return []
        }
    }

    private static func danceSessionExercises(minutes: Int, calories: Double) -> [PlannedExercise] {
        [
            PlannedExercise(
                name: "舞蹈团课",
                muscleGroup: "有氧",
                equipment: "舞室",
                sets: 1,
                reps: "\(minutes)分钟",
                restSeconds: 0,
                targetCalories: calories,
                notes: "建议 19:00 左右开始；以团课/舞室练习为主，无需拆解器械动作",
                exerciseKind: "cardio"
            )
        ]
    }

    private static func swimmingSessionExercises(minutes: Int, calories: Double) -> [PlannedExercise] {
        let meters = max(minutes * 20, 600)
        return [
            PlannedExercise(
                name: "蛙泳",
                muscleGroup: "有氧",
                equipment: "泳池",
                sets: 1,
                reps: "\(meters)米",
                restSeconds: 0,
                targetCalories: calories,
                notes: "约 \(minutes) 分钟 · 热身 200m + 主项 \(max(meters - 400, 400))m + 放松 200m",
                exerciseKind: "cardio"
            )
        ]
    }

    private static func coreCardioExercises(phase: CyclePhase) -> [PlannedExercise] {
        let light = phase == .menstrual || phase == .luteal
        if light {
            return [
                PlannedExercise(name: "死虫", muscleGroup: "核心", equipment: "瑜伽垫", sets: 3, reps: "12/侧", restSeconds: 30, targetCalories: 18, notes: "腰贴地", exerciseKind: "strength"),
                PlannedExercise(name: "平板支撑", muscleGroup: "核心", equipment: "自重", sets: 3, reps: "30秒", restSeconds: 30, targetCalories: 20, notes: "", exerciseKind: "strength"),
                PlannedExercise(name: "鸟狗式", muscleGroup: "核心", equipment: "瑜伽垫", sets: 3, reps: "10/侧", restSeconds: 25, targetCalories: 15, notes: "", exerciseKind: "mobility"),
                PlannedExercise(name: "快走", muscleGroup: "有氧", equipment: "—", sets: 1, reps: "20分钟", restSeconds: 0, targetCalories: 100, notes: "稳态有氧", exerciseKind: "cardio")
            ]
        }
        return [
            PlannedExercise(name: "平板支撑", muscleGroup: "核心", equipment: "自重", sets: 3, reps: "45秒", restSeconds: 30, targetCalories: 22, notes: "", exerciseKind: "strength"),
            PlannedExercise(name: "俄罗斯转体", muscleGroup: "核心", equipment: "哑铃", sets: 3, reps: "20", restSeconds: 30, targetCalories: 25, notes: "", exerciseKind: "strength"),
            PlannedExercise(name: "登山跑", muscleGroup: "核心", equipment: "自重", sets: 3, reps: "30秒", restSeconds: 30, targetCalories: 30, notes: "核心收紧", exerciseKind: "cardio"),
            PlannedExercise(name: "HIIT 循环", muscleGroup: "有氧", equipment: "自重", sets: 1, reps: "15分钟", restSeconds: 0, targetCalories: 120, notes: "开合跳+高抬腿交替", exerciseKind: "cardio")
        ]
    }

    private static func fullBodyExercises(phase: CyclePhase) -> [PlannedExercise] {
        let light = phase == .menstrual || phase == .luteal
        if light {
            return [
                PlannedExercise(name: "杯式深蹲", muscleGroup: "腿", equipment: "哑铃", sets: 3, reps: "12", restSeconds: 60, targetCalories: 42, notes: "", exerciseKind: "strength"),
                PlannedExercise(name: "弹力带划船", muscleGroup: "背", equipment: "弹力带", sets: 3, reps: "15", restSeconds: 45, targetCalories: 35, notes: "", exerciseKind: "strength"),
                PlannedExercise(name: "跪姿俯卧撑", muscleGroup: "胸", equipment: "自重", sets: 3, reps: "10", restSeconds: 45, targetCalories: 28, notes: "", exerciseKind: "strength"),
                PlannedExercise(name: "臀桥", muscleGroup: "臀", equipment: "自重", sets: 3, reps: "15", restSeconds: 40, targetCalories: 30, notes: "全身复合", exerciseKind: "strength")
            ]
        }
        return [
            PlannedExercise(name: "杠铃深蹲", muscleGroup: "腿", equipment: "杠铃", sets: 4, reps: "10", restSeconds: 90, targetCalories: 65, notes: "全身主导", exerciseKind: "strength"),
            PlannedExercise(name: "哑铃划船", muscleGroup: "背", equipment: "哑铃", sets: 4, reps: "12", restSeconds: 60, targetCalories: 48, notes: "", exerciseKind: "strength"),
            PlannedExercise(name: "哑铃卧推", muscleGroup: "胸", equipment: "哑铃", sets: 3, reps: "12", restSeconds: 60, targetCalories: 42, notes: "", exerciseKind: "strength"),
            PlannedExercise(name: "罗马尼亚硬拉", muscleGroup: "臀腿", equipment: "哑铃", sets: 3, reps: "10", restSeconds: 75, targetCalories: 50, notes: "", exerciseKind: "strength"),
            PlannedExercise(name: "农夫行走", muscleGroup: "全身", equipment: "哑铃", sets: 3, reps: "40米", restSeconds: 60, targetCalories: 35, notes: "核心稳定", exerciseKind: "strength")
        ]
    }

    private static func pushDayExercises(phase: CyclePhase) -> [PlannedExercise] {
        let light = phase == .menstrual || phase == .luteal
        if light {
            return [
                PlannedExercise(name: "跪姿俯卧撑", muscleGroup: "胸", equipment: "自重", sets: 3, reps: "12", restSeconds: 45, targetCalories: 30, notes: "", exerciseKind: "strength"),
                PlannedExercise(name: "哑铃肩推", muscleGroup: "肩", equipment: "哑铃", sets: 3, reps: "12", restSeconds: 60, targetCalories: 35, notes: "核心收紧", exerciseKind: "strength"),
                PlannedExercise(name: "侧平举", muscleGroup: "肩", equipment: "哑铃", sets: 3, reps: "15", restSeconds: 45, targetCalories: 22, notes: "", exerciseKind: "strength"),
                PlannedExercise(name: "凳上臂屈伸", muscleGroup: "三头", equipment: "自重", sets: 3, reps: "12", restSeconds: 45, targetCalories: 25, notes: "", exerciseKind: "strength")
            ]
        }
        return [
            PlannedExercise(name: "哑铃卧推", muscleGroup: "胸", equipment: "哑铃", sets: 4, reps: "10", restSeconds: 75, targetCalories: 50, notes: "肩胛稳定", exerciseKind: "strength"),
            PlannedExercise(name: "哑铃肩推", muscleGroup: "肩", equipment: "哑铃", sets: 4, reps: "10", restSeconds: 75, targetCalories: 45, notes: "", exerciseKind: "strength"),
            PlannedExercise(name: "侧平举", muscleGroup: "肩", equipment: "哑铃", sets: 3, reps: "15", restSeconds: 45, targetCalories: 25, notes: "", exerciseKind: "strength"),
            PlannedExercise(name: "绳索下压", muscleGroup: "三头", equipment: "器械", sets: 3, reps: "12", restSeconds: 45, targetCalories: 28, notes: "", exerciseKind: "strength"),
            PlannedExercise(name: "俯卧撑", muscleGroup: "胸", equipment: "自重", sets: 3, reps: "力竭", restSeconds: 60, targetCalories: 35, notes: "收尾", exerciseKind: "strength")
        ]
    }

    private static func pullDayExercises(phase: CyclePhase) -> [PlannedExercise] {
        let light = phase == .menstrual || phase == .luteal
        if light {
            return [
                PlannedExercise(name: "弹力带划船", muscleGroup: "背", equipment: "弹力带", sets: 3, reps: "15", restSeconds: 60, targetCalories: 35, notes: "肩胛后缩", exerciseKind: "strength"),
                PlannedExercise(name: "直臂下拉", muscleGroup: "背", equipment: "器械", sets: 3, reps: "12", restSeconds: 45, targetCalories: 30, notes: "", exerciseKind: "strength"),
                PlannedExercise(name: "面拉", muscleGroup: "肩", equipment: "弹力带", sets: 3, reps: "15", restSeconds: 45, targetCalories: 22, notes: "后束", exerciseKind: "strength"),
                PlannedExercise(name: "哑铃弯举", muscleGroup: "二头", equipment: "哑铃", sets: 3, reps: "12", restSeconds: 45, targetCalories: 25, notes: "", exerciseKind: "strength")
            ]
        }
        return [
            PlannedExercise(name: "高位下拉", muscleGroup: "背", equipment: "器械", sets: 4, reps: "12", restSeconds: 60, targetCalories: 55, notes: "控制离心", exerciseKind: "strength"),
            PlannedExercise(name: "坐姿划船", muscleGroup: "背", equipment: "器械", sets: 4, reps: "12", restSeconds: 60, targetCalories: 50, notes: "", exerciseKind: "strength"),
            PlannedExercise(name: "面拉", muscleGroup: "肩", equipment: "绳索", sets: 3, reps: "15", restSeconds: 45, targetCalories: 28, notes: "后束", exerciseKind: "strength"),
            PlannedExercise(name: "哑铃弯举", muscleGroup: "二头", equipment: "哑铃", sets: 3, reps: "12", restSeconds: 45, targetCalories: 28, notes: "", exerciseKind: "strength"),
            PlannedExercise(name: "锤式弯举", muscleGroup: "二头", equipment: "哑铃", sets: 3, reps: "12", restSeconds: 45, targetCalories: 25, notes: "", exerciseKind: "strength")
        ]
    }

    private static func legsDayExercises(phase: CyclePhase) -> [PlannedExercise] {
        glutesLegsExercises(phase: phase)
    }

    private static func glutesLegsExercises(phase: CyclePhase) -> [PlannedExercise] {
        let light = phase == .menstrual || phase == .luteal
        if light {
            return [
                PlannedExercise(name: "杯式深蹲", muscleGroup: "腿", equipment: "哑铃", sets: 3, reps: "12", restSeconds: 60, targetCalories: 42, notes: "膝盖对齐脚尖", exerciseKind: "strength"),
                PlannedExercise(name: "臀桥", muscleGroup: "臀", equipment: "自重", sets: 4, reps: "15", restSeconds: 45, targetCalories: 35, notes: "顶峰收缩", exerciseKind: "strength"),
                PlannedExercise(name: "保加利亚分腿蹲", muscleGroup: "腿", equipment: "自重", sets: 3, reps: "10/侧", restSeconds: 60, targetCalories: 40, notes: "", exerciseKind: "strength"),
                PlannedExercise(name: "蚌式开合", muscleGroup: "臀", equipment: "自重", sets: 3, reps: "15", restSeconds: 30, targetCalories: 18, notes: "侧臀", exerciseKind: "strength")
            ]
        }
        return [
            PlannedExercise(name: "杠铃深蹲", muscleGroup: "腿", equipment: "杠铃", sets: 4, reps: "10", restSeconds: 90, targetCalories: 70, notes: "髋主导", exerciseKind: "strength"),
            PlannedExercise(name: "罗马尼亚硬拉", muscleGroup: "臀腿", equipment: "哑铃", sets: 4, reps: "10", restSeconds: 75, targetCalories: 55, notes: "背打平", exerciseKind: "strength"),
            PlannedExercise(name: "臀推", muscleGroup: "臀", equipment: "杠铃", sets: 4, reps: "12", restSeconds: 75, targetCalories: 50, notes: "", exerciseKind: "strength"),
            PlannedExercise(name: "弓步蹲", muscleGroup: "腿", equipment: "哑铃", sets: 3, reps: "12/侧", restSeconds: 60, targetCalories: 45, notes: "", exerciseKind: "strength"),
            PlannedExercise(name: "腿弯举", muscleGroup: "腿", equipment: "器械", sets: 3, reps: "12", restSeconds: 45, targetCalories: 30, notes: "", exerciseKind: "strength")
        ]
    }

    private static func shouldersBackExercises(phase: CyclePhase) -> [PlannedExercise] {
        let light = phase == .menstrual || phase == .luteal
        if light {
            return [
                PlannedExercise(name: "弹力带划船", muscleGroup: "背", equipment: "弹力带", sets: 3, reps: "15", restSeconds: 60, targetCalories: 35, notes: "", exerciseKind: "strength"),
                PlannedExercise(name: "YTWL", muscleGroup: "肩", equipment: "自重", sets: 2, reps: "10", restSeconds: 30, targetCalories: 18, notes: "肩胛稳定", exerciseKind: "strength"),
                PlannedExercise(name: "面拉", muscleGroup: "肩", equipment: "弹力带", sets: 3, reps: "15", restSeconds: 45, targetCalories: 22, notes: "", exerciseKind: "strength"),
                PlannedExercise(name: "反向飞鸟", muscleGroup: "肩", equipment: "哑铃", sets: 3, reps: "15", restSeconds: 45, targetCalories: 25, notes: "后束", exerciseKind: "strength")
            ]
        }
        return [
            PlannedExercise(name: "引体向上/高位下拉", muscleGroup: "背", equipment: "器械", sets: 4, reps: "10", restSeconds: 75, targetCalories: 55, notes: "", exerciseKind: "strength"),
            PlannedExercise(name: "坐姿划船", muscleGroup: "背", equipment: "器械", sets: 4, reps: "12", restSeconds: 60, targetCalories: 50, notes: "", exerciseKind: "strength"),
            PlannedExercise(name: "哑铃肩推", muscleGroup: "肩", equipment: "哑铃", sets: 4, reps: "10", restSeconds: 75, targetCalories: 45, notes: "", exerciseKind: "strength"),
            PlannedExercise(name: "侧平举", muscleGroup: "肩", equipment: "哑铃", sets: 3, reps: "15", restSeconds: 45, targetCalories: 25, notes: "", exerciseKind: "strength"),
            PlannedExercise(name: "面拉", muscleGroup: "肩", equipment: "绳索", sets: 3, reps: "15", restSeconds: 45, targetCalories: 28, notes: "后束", exerciseKind: "strength")
        ]
    }

    private static func strengthExerciseBlock(phase: CyclePhase) -> [PlannedExercise] {
        switch phase {
        case .menstrual, .luteal:
            return [
                PlannedExercise(name: "弹力带划船", muscleGroup: "背", equipment: "弹力带", sets: 3, reps: "15", restSeconds: 60, targetCalories: 40, notes: "肩胛后缩", exerciseKind: "strength"),
                PlannedExercise(name: "杯式深蹲", muscleGroup: "腿", equipment: "哑铃", sets: 3, reps: "12", restSeconds: 60, targetCalories: 45, notes: "膝盖对齐脚尖", exerciseKind: "strength"),
                PlannedExercise(name: "跪姿俯卧撑", muscleGroup: "胸", equipment: "自重", sets: 3, reps: "10", restSeconds: 45, targetCalories: 30, notes: "", exerciseKind: "strength"),
                PlannedExercise(name: "平板支撑", muscleGroup: "核心", equipment: "自重", sets: 3, reps: "30秒", restSeconds: 30, targetCalories: 20, notes: "", exerciseKind: "strength")
            ]
        default:
            return [
                PlannedExercise(name: "高位下拉", muscleGroup: "背", equipment: "器械", sets: 4, reps: "12", restSeconds: 60, targetCalories: 55, notes: "控制离心", exerciseKind: "strength"),
                PlannedExercise(name: "杠铃深蹲", muscleGroup: "腿", equipment: "杠铃", sets: 4, reps: "10", restSeconds: 90, targetCalories: 70, notes: "髋主导", exerciseKind: "strength"),
                PlannedExercise(name: "哑铃卧推", muscleGroup: "胸", equipment: "哑铃", sets: 3, reps: "12", restSeconds: 60, targetCalories: 45, notes: "", exerciseKind: "strength"),
                PlannedExercise(name: "罗马尼亚硬拉", muscleGroup: "臀腿", equipment: "哑铃", sets: 3, reps: "10", restSeconds: 75, targetCalories: 50, notes: "背打平", exerciseKind: "strength"),
                PlannedExercise(name: "侧平举", muscleGroup: "肩", equipment: "哑铃", sets: 3, reps: "15", restSeconds: 45, targetCalories: 25, notes: "", exerciseKind: "strength")
            ]
        }
    }

    private static func estimatedSessionCalories(minutes: Int, intensity: String) -> Double {
        estimatedSessionCaloriesPublic(minutes: minutes, intensity: intensity)
    }

    static func estimatedSessionCaloriesPublic(minutes: Int, intensity: String) -> Double {
        let factor: Double
        switch intensity {
        case "high": factor = 9
        case "low": factor = 5
        default: factor = 7
        }
        return Double(minutes) * factor
    }

    // MARK: - Scheduling

    /// 场地项目（舞蹈/游泳）优先工作日晚间
    private static func facilityWeekdaySlots(for count: Int) -> [Int] {
        switch count {
        case 2: return [2, 4]
        case 3: return [2, 4, 6]
        case 4: return [2, 3, 4, 6]
        case 5: return [2, 3, 4, 5, 6]
        default: return [2, 3, 4, 5, 6, 7]
        }
    }

    /// 周一优先的训练日分布（Calendar.weekday）
    private static func weekdaySlots(for count: Int) -> [Int] {
        switch count {
        case 2: return [2, 5]
        case 3: return [2, 4, 6]
        case 4: return [2, 3, 5, 6]
        case 5: return [2, 3, 4, 5, 6]
        default: return [2, 3, 4, 5, 6, 7]
        }
    }

    struct SessionTemplate {
        var type: String
        var minutes: Int
        var intensity: String
        var note: String
    }

    private static func sessionTemplates(
        for phase: CyclePhase,
        count: Int,
        activityLevel: String,
        planType: WorkoutPlanType
    ) -> [SessionTemplate] {
        let boost = activityBoost(activityLevel)
        let templates: [SessionTemplate]
        switch planType {
        case .balanced:
            templates = balancedTemplates(for: phase, count: count, boost: boost)
        case .threeDaySplit:
            templates = threeDaySplitTemplates(count: count, boost: boost, phase: phase)
        case .threeDaySplitPlusCardio:
            templates = threeDaySplitPlusCardioTemplates(count: count, boost: boost, phase: phase)
        case .glutesLegs:
            templates = glutesLegsTemplates(count: count, boost: boost, phase: phase)
        case .shouldersBack:
            templates = shouldersBackTemplates(count: count, boost: boost, phase: phase)
        case .cardioFocus:
            templates = cardioFocusTemplates(count: count, boost: boost, phase: phase)
        case .dance:
            templates = danceTemplates(count: count, boost: boost, phase: phase)
        case .swimming:
            templates = swimmingTemplates(count: count, boost: boost, phase: phase)
        }
        return Array(templates.prefix(count))
    }

    private static func danceTemplates(count: Int, boost: Int, phase: CyclePhase) -> [SessionTemplate] {
        let minutes = (phase == .menstrual || phase == .luteal) ? 50 + boost : 60 + boost
        let intensity = (phase == .menstrual || phase == .luteal) ? "medium" : "high"
        let cycle = [
            SessionTemplate(type: "舞蹈", minutes: minutes, intensity: intensity, note: "建议 19:00 · 舞室/团课"),
            SessionTemplate(type: "舞蹈", minutes: minutes - 5, intensity: "medium", note: "建议 19:00 · 有氧舞")
        ]
        return expandCycle(cycle, count: count)
    }

    private static func swimmingTemplates(count: Int, boost: Int, phase: CyclePhase) -> [SessionTemplate] {
        let minutes = (phase == .menstrual || phase == .luteal) ? 35 + boost : 40 + boost
        let intensity = "medium"
        let cycle = [
            SessionTemplate(type: "游泳", minutes: minutes, intensity: intensity, note: "蛙泳 · 建议 19:00"),
            SessionTemplate(type: "游泳", minutes: minutes + 5, intensity: intensity, note: "蛙泳 · 距离递增")
        ]
        return expandCycle(cycle, count: count)
    }

    private static func balancedTemplates(
        for phase: CyclePhase,
        count: Int,
        boost: Int
    ) -> [SessionTemplate] {
        switch phase {
        case .menstrual:
            return menstrualTemplates(count: count, boost: boost)
        case .follicular:
            return follicularTemplates(count: count, boost: boost)
        case .luteal:
            return lutealTemplates(count: count, boost: boost)
        case .unknown:
            return follicularTemplates(count: count, boost: boost).map {
                var copy = $0
                copy.note = "设置生理周期后可获得更精准强度建议"
                return copy
            }
        }
    }

    private static func threeDaySplitTemplates(count: Int, boost: Int, phase: CyclePhase) -> [SessionTemplate] {
        let intensity = (phase == .menstrual || phase == .luteal) ? "medium" : "high"
        let minutes = (phase == .menstrual || phase == .luteal) ? 40 + boost : 45 + boost
        let cycle: [SessionTemplate] = [
            SessionTemplate(type: "三分化·肩背", minutes: minutes, intensity: intensity, note: "背、肩为主；划船、下拉、推举"),
            SessionTemplate(type: "三分化·臀腿", minutes: minutes + 5, intensity: intensity, note: "臀腿主导；深蹲、硬拉、臀推"),
            SessionTemplate(type: "三分化·核心有氧", minutes: minutes, intensity: intensity, note: "核心激活 + 有氧消耗")
        ]
        return expandCycle(cycle, count: count)
    }

    private static func threeDaySplitPlusCardioTemplates(count: Int, boost: Int, phase: CyclePhase) -> [SessionTemplate] {
        let intensity = (phase == .menstrual || phase == .luteal) ? "medium" : "high"
        let minutes = (phase == .menstrual || phase == .luteal) ? 40 + boost : 45 + boost
        let cycle: [SessionTemplate] = [
            SessionTemplate(type: "三分化·肩背", minutes: minutes, intensity: intensity, note: "背、肩为主"),
            SessionTemplate(type: "三分化·臀腿", minutes: minutes + 5, intensity: intensity, note: "臀腿主导"),
            SessionTemplate(type: "三分化·核心有氧", minutes: minutes, intensity: intensity, note: "核心 + 有氧"),
            SessionTemplate(type: "全身训练", minutes: minutes, intensity: intensity, note: "复合动作为主，全身协调")
        ]
        return expandCycle(cycle, count: count)
    }

    /// 按用户选择的单场侧重重建动作清单
    static func exercisesForFocus(
        _ focus: WorkoutSessionFocus,
        minutes: Int,
        intensity: String,
        phase: CyclePhase
    ) -> [PlannedExercise] {
        let template = SessionTemplate(
            type: focus.engineWorkoutType,
            minutes: minutes,
            intensity: intensity,
            note: ""
        )
        return exercisesForTemplate(template, phase: phase)
    }

    private static func glutesLegsTemplates(count: Int, boost: Int, phase: CyclePhase) -> [SessionTemplate] {
        let intensity = (phase == .menstrual || phase == .luteal) ? "medium" : "high"
        let minutes = 45 + boost
        var pool: [SessionTemplate] = [
            SessionTemplate(type: "臀腿专项", minutes: minutes, intensity: intensity, note: "深蹲、硬拉、臀推为主"),
            SessionTemplate(type: "臀腿专项", minutes: minutes - 5, intensity: "medium", note: "弓步、臀桥、侧臀激活"),
            SessionTemplate(type: "臀腿专项", minutes: minutes, intensity: intensity, note: "下肢力量 + 核心稳定")
        ]
        if count >= 4 {
            pool.append(cardioRecoveryTemplate(boost: boost, phase: phase))
        }
        return expandCycle(pool, count: count)
    }

    private static func shouldersBackTemplates(count: Int, boost: Int, phase: CyclePhase) -> [SessionTemplate] {
        let intensity = (phase == .menstrual || phase == .luteal) ? "medium" : "high"
        let minutes = 42 + boost
        var pool: [SessionTemplate] = [
            SessionTemplate(type: "肩背专项", minutes: minutes, intensity: intensity, note: "划船、下拉、面拉"),
            SessionTemplate(type: "肩背专项", minutes: minutes, intensity: intensity, note: "肩推、侧平举、反向飞鸟"),
            SessionTemplate(type: "肩背专项", minutes: minutes - 5, intensity: "medium", note: "肩胛稳定 + 后束")
        ]
        if count >= 4 {
            pool.append(cardioRecoveryTemplate(boost: boost, phase: phase))
        }
        return expandCycle(pool, count: count)
    }

    private static func cardioFocusTemplates(count: Int, boost: Int, phase: CyclePhase) -> [SessionTemplate] {
        let low = phase == .menstrual || phase == .luteal
        let pool: [SessionTemplate] = low
            ? [
                SessionTemplate(type: "快走", minutes: 40 + boost, intensity: "low", note: "稳态有氧，心率平稳"),
                SessionTemplate(type: "椭圆机", minutes: 35 + boost, intensity: "medium", note: "低冲击有氧"),
                SessionTemplate(type: "瑜伽", minutes: 30 + boost, intensity: "low", note: "主动恢复"),
                SessionTemplate(type: "骑行", minutes: 40 + boost, intensity: "medium", note: "中等强度"),
                SessionTemplate(type: "游泳", minutes: 35 + boost, intensity: "medium", note: "全身有氧"),
                SessionTemplate(type: "散步", minutes: 30 + boost, intensity: "low", note: "放松")
            ]
            : [
                SessionTemplate(type: "HIIT", minutes: 25 + boost / 2, intensity: "high", note: "间歇燃脂"),
                SessionTemplate(type: "跑步", minutes: 35 + boost, intensity: "medium", note: "有氧耐力"),
                SessionTemplate(type: "骑行", minutes: 45 + boost, intensity: "medium", note: "持续有氧"),
                SessionTemplate(type: "椭圆机", minutes: 40 + boost, intensity: "medium", note: "低冲击"),
                SessionTemplate(type: "游泳", minutes: 40 + boost, intensity: "medium", note: "全身有氧"),
                SessionTemplate(type: "快走", minutes: 35 + boost, intensity: "medium", note: "稳态恢复")
            ]
        return Array(pool.prefix(count))
    }

    private static func cardioRecoveryTemplate(boost: Int, phase: CyclePhase) -> SessionTemplate {
        if phase == .menstrual || phase == .luteal {
            return SessionTemplate(type: "快走", minutes: 30 + boost, intensity: "low", note: "训练日之间的主动恢复")
        }
        return SessionTemplate(type: "椭圆机", minutes: 30 + boost, intensity: "medium", note: "低冲击有氧恢复")
    }

    private static func expandCycle(_ cycle: [SessionTemplate], count: Int) -> [SessionTemplate] {
        guard !cycle.isEmpty else { return [] }
        return (0..<count).map { cycle[$0 % cycle.count] }
    }

    private static func activityBoost(_ level: String) -> Int {
        switch level {
        case "sedentary": return -5
        case "light": return 0
        case "moderate": return 5
        case "active", "very_active": return 10
        default: return 0
        }
    }

    private static func menstrualTemplates(count: Int, boost: Int) -> [SessionTemplate] {
        let pool: [SessionTemplate] = [
            SessionTemplate(type: "瑜伽", minutes: 30 + boost, intensity: "low", note: "舒缓拉伸，避免腹部加压"),
            SessionTemplate(type: "快走", minutes: 35 + boost, intensity: "low", note: "保持心率平稳"),
            SessionTemplate(type: "散步", minutes: 25 + boost, intensity: "low", note: "户外放松"),
            SessionTemplate(type: "普拉提", minutes: 30 + boost, intensity: "low", note: "核心温和激活"),
            SessionTemplate(type: "休息", minutes: 20, intensity: "low", note: "主动恢复或轻度拉伸"),
            SessionTemplate(type: "太极", minutes: 30, intensity: "low", note: "放松身心")
        ]
        return Array(pool.prefix(count))
    }

    private static func follicularTemplates(count: Int, boost: Int) -> [SessionTemplate] {
        let pool: [SessionTemplate] = [
            SessionTemplate(type: "力量训练", minutes: 45 + boost, intensity: "high", note: "重点大肌群，注意动作标准"),
            SessionTemplate(type: "HIIT", minutes: 20 + boost / 2, intensity: "high", note: "间歇训练，充分热身"),
            SessionTemplate(type: "跑步", minutes: 35 + boost, intensity: "medium", note: "有氧耐力"),
            SessionTemplate(type: "游泳", minutes: 40 + boost, intensity: "medium", note: "全身有氧"),
            SessionTemplate(type: "力量训练", minutes: 40 + boost, intensity: "medium", note: "上肢或下肢分化"),
            SessionTemplate(type: "骑行", minutes: 45 + boost, intensity: "medium", note: "中等强度有氧")
        ]
        return Array(pool.prefix(count))
    }

    private static func lutealTemplates(count: Int, boost: Int) -> [SessionTemplate] {
        let pool: [SessionTemplate] = [
            SessionTemplate(type: "快走", minutes: 40 + boost, intensity: "medium", note: "黄体期适合稳态有氧"),
            SessionTemplate(type: "瑜伽", minutes: 35 + boost, intensity: "low", note: "降低皮质醇，放松"),
            SessionTemplate(type: "普拉提", minutes: 35 + boost, intensity: "medium", note: "核心稳定"),
            SessionTemplate(type: "力量训练", minutes: 35 + boost, intensity: "medium", note: "中等重量，避免力竭"),
            SessionTemplate(type: "休息", minutes: 20, intensity: "low", note: "散步或拉伸"),
            SessionTemplate(type: "椭圆机", minutes: 35 + boost, intensity: "medium", note: "低冲击有氧")
        ]
        return Array(pool.prefix(count))
    }

    private static func moderateMinutesGoal(phase: CyclePhase, sessions: Int, activityLevel: String) -> Int {
        let base: Int
        switch phase {
        case .menstrual: base = 90
        case .follicular: base = 150
        case .luteal: base = 120
        case .unknown: base = 120
        }
        let sessionBonus = max(sessions - 3, 0) * 15
        let activityBonus: Int
        switch activityLevel {
        case "active", "very_active": activityBonus = 20
        case "moderate": activityBonus = 10
        default: activityBonus = 0
        }
        return base + sessionBonus + activityBonus
    }

    private static func strengthSessionsGoal(phase: CyclePhase, sessions: [PlannedSession]) -> Int {
        let count = sessions.filter { isStrengthWorkoutType($0.workoutType) }.count
        switch phase {
        case .menstrual: return min(count, 1)
        case .follicular: return max(count, 2)
        case .luteal: return min(max(count, 1), 2)
        case .unknown: return count
        }
    }

    // MARK: - Diet & summary

    private static func buildDietAdvice(
        input: Input,
        split: WorkoutNutritionPlanner.SplitNutritionPlan
    ) -> String {
        var lines: [String] = []

        let t = split.trainingDay
        let r = split.restDay
        lines.append("训练日：\(Int(t.caloriesKcal)) kcal · 蛋白 \(Int(t.proteinGrams))g · 碳水 \(Int(t.carbGrams))g · 脂肪 \(Int(t.fatGrams))g")
        lines.append("休息日：\(Int(r.caloriesKcal)) kcal · 蛋白 \(Int(r.proteinGrams))g · 碳水 \(Int(r.carbGrams))g · 脂肪 \(Int(r.fatGrams))g")
        if !t.notes.isEmpty { lines.append("训练日：\(t.notes)") }
        if !r.notes.isEmpty { lines.append("休息日：\(r.notes)") }

        if let budget = input.dailyCalorieBudget {
            lines.append("热量预算约 \(Int(budget)) 大卡，训练日可适当增加 100–150 大卡优质碳水。")
        }
        if let protein = input.proteinTargetGrams, protein > 0 {
            lines.append("蛋白质目标约 \(Int(protein)) g/天，训练后 30 分钟内补充 20–30 g 蛋白。")
        }
        if let current = input.currentWeight, let target = input.targetWeight, current > target {
            let delta = current - target
            lines.append("当前距目标体重约 \(String(format: "%.1f", delta)) kg，建议维持适度热量缺口，避免过度节食影响训练恢复。")
        }

        if !input.healthDietNotes.isEmpty {
            lines.append("体检饮食提示：" + input.healthDietNotes.prefix(3).joined(separator: "；"))
        }
        if !input.riskHints.isEmpty {
            lines.append("健康关注：" + input.riskHints.prefix(2).joined(separator: "；"))
        }

        lines.append(input.cycleWorkoutTip)
        lines.append("以上内容仅供参考，请遵医嘱。")
        return lines.joined(separator: "\n")
    }

    private static func buildWeeklySummary(
        input: Input,
        sessions: [PlannedSession],
        moderateGoal: Int,
        strengthGoal: Int,
        weeklyBurn: Double,
        planType: WorkoutPlanType
    ) -> String {
        let phaseLabel = input.phase.rawValue
        let totalMinutes = sessions.reduce(0) { $0 + $1.targetMinutes }
        var line = "\(planType.label) · \(phaseLabel) · 本周 \(sessions.count) 练 · 目标消耗 \(Int(weeklyBurn)) kcal · \(totalMinutes) 分钟"
        if let deficit = input.dailyDeficitTarget, deficit > 0 {
            line += " · 配合每日 \(Int(deficit)) kcal 减脂缺口"
        }
        line += " · 近 7 天已运动 \(input.recentWorkoutCount7d) 次"
        return line
    }

    private static func isStrengthWorkoutType(_ type: String) -> Bool {
        type.contains("力量")
            || type.contains("三分化")
            || type.contains("专项")
    }
}
