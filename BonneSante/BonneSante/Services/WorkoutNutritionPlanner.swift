import Foundation

/// 训练计划配套每日营养目标与摄入超标加练估算
/// @author jiali.qiu
enum WorkoutNutritionPlanner {

    struct DailyNutritionPlan: Equatable, Codable {
        var caloriesKcal: Double
        var proteinGrams: Double
        var carbGrams: Double
        var fatGrams: Double
        var notes: String
    }

    /// 训练日 / 休息日分日营养（首页与营养 Tab 按当日是否排课切换）
    struct SplitNutritionPlan: Equatable, Codable {
        var trainingDay: DailyNutritionPlan
        var restDay: DailyNutritionPlan
    }

    struct SurplusExerciseHint: Equatable {
        var surplusKcal: Double
        var suggestedMinutes: Int
        var message: String
    }

    /// 本周单日营养目标（用于周视图，非双列对比）
    struct WeeklyNutritionDay: Identifiable, Equatable {
        var id: Date
        var weekdayShort: String
        var isTrainingDay: Bool
        var plan: DailyNutritionPlan
        var calorieDeltaFromBaseline: Int?
        var isToday: Bool
    }

    /// 由减脂引擎宏量目标生成规则版训练日营养
    static func fromEngine(
        dailyBudget: Double?,
        proteinGrams: Double?,
        carbGrams: Double?,
        fatGrams: Double?,
        phase: CyclePhase
    ) -> DailyNutritionPlan {
        let calories = max(dailyBudget ?? 0, 1200)
        let protein = max(proteinGrams ?? calories * 0.28 / 4, 60)
        let fat = max(fatGrams ?? calories * 0.28 / 9, 35)
        var carbs = max(carbGrams ?? 0, 0)
        if carbs <= 0, calories > 0 {
            let remaining = calories - protein * 4 - fat * 9
            carbs = max(remaining / 4, 80)
        }
        if phase == .follicular {
            carbs = min(carbs * 1.08, calories * 0.45 / 4)
        }
        let note = phase == .menstrual
            ? "经期适当保证蛋白与铁，碳水可略宽松。"
            : "与本周训练消耗目标配合。"
        return DailyNutritionPlan(
            caloriesKcal: calories,
            proteinGrams: protein.rounded(),
            carbGrams: carbs.rounded(),
            fatGrams: fat.rounded(),
            notes: note
        )
    }

    /// 规则引擎：由基准预算推导训练日（+碳水/热量）与休息日（降碳水/热量）
    static func fromEngineSplit(
        dailyBudget: Double?,
        proteinGrams: Double?,
        carbGrams: Double?,
        fatGrams: Double?,
        phase: CyclePhase
    ) -> SplitNutritionPlan {
        let base = fromEngine(
            dailyBudget: dailyBudget,
            proteinGrams: proteinGrams,
            carbGrams: carbGrams,
            fatGrams: fatGrams,
            phase: phase
        )

        var training = base
        training.caloriesKcal = base.caloriesKcal + 80
        training.carbGrams = min(base.carbGrams * 1.15, training.caloriesKcal * 0.45 / 4).rounded()
        training.notes = "训练日提高碳水以支持消耗与恢复。"

        var rest = base
        rest.caloriesKcal = max(base.caloriesKcal - 120, 1200)
        rest.carbGrams = max(base.carbGrams * 0.82, 65).rounded()
        rest.proteinGrams = base.proteinGrams
        rest.fatGrams = base.fatGrams
        rest.notes = "休息日适当降低碳水与总热量，蛋白维持。"

        return SplitNutritionPlan(trainingDay: training, restDay: rest)
    }

    /// 写入训练偏好（训练日 → daily* 字段，休息日 → restDay* 字段）
    static func apply(_ split: SplitNutritionPlan, source: String, to prefs: WorkoutPlanPreferences) {
        applyTrainingDay(split.trainingDay, source: source, to: prefs)
        prefs.restDayCalorieTargetKcal = split.restDay.caloriesKcal
        prefs.restDayProteinGrams = split.restDay.proteinGrams
        prefs.restDayCarbGrams = split.restDay.carbGrams
        prefs.restDayFatGrams = split.restDay.fatGrams
        prefs.restDayNotes = split.restDay.notes
        prefs.updatedAt = Date()
    }

    /// 兼容旧版单一日营养写入
    static func apply(_ plan: DailyNutritionPlan, source: String, to prefs: WorkoutPlanPreferences) {
        applyTrainingDay(plan, source: source, to: prefs)
        let rest = deriveRestDay(from: plan)
        prefs.restDayCalorieTargetKcal = rest.caloriesKcal
        prefs.restDayProteinGrams = rest.proteinGrams
        prefs.restDayCarbGrams = rest.carbGrams
        prefs.restDayFatGrams = rest.fatGrams
        prefs.restDayNotes = rest.notes
        prefs.updatedAt = Date()
    }

    private static func applyTrainingDay(_ plan: DailyNutritionPlan, source: String, to prefs: WorkoutPlanPreferences) {
        prefs.dailyCalorieTargetKcal = plan.caloriesKcal
        prefs.dailyProteinGrams = plan.proteinGrams
        prefs.dailyCarbGrams = plan.carbGrams
        prefs.dailyFatGrams = plan.fatGrams
        prefs.nutritionPlanSource = source
        prefs.nutritionNotes = plan.notes
    }

    static func deriveRestDayFromTraining(_ training: DailyNutritionPlan) -> DailyNutritionPlan {
        deriveRestDay(from: training)
    }

    private static func deriveRestDay(from training: DailyNutritionPlan) -> DailyNutritionPlan {
        DailyNutritionPlan(
            caloriesKcal: max(training.caloriesKcal - 120, 1200),
            proteinGrams: training.proteinGrams,
            carbGrams: max(training.carbGrams * 0.82, 65).rounded(),
            fatGrams: training.fatGrams,
            notes: "休息日适当降低碳水与总热量，蛋白维持。"
        )
    }

    static func hasActivePlan(_ prefs: WorkoutPlanPreferences?) -> Bool {
        guard let prefs else { return false }
        return prefs.dailyProteinGrams > 0 && !prefs.nutritionPlanSource.isEmpty
    }

    static func hasSplitPlan(_ prefs: WorkoutPlanPreferences?) -> Bool {
        guard let prefs else { return false }
        return hasActivePlan(prefs) && prefs.restDayProteinGrams > 0
    }

    /// 按今日是否排课返回生效营养目标
    static func effectivePlan(_ prefs: WorkoutPlanPreferences, isTrainingDay: Bool) -> DailyNutritionPlan {
        if hasSplitPlan(prefs) {
            return isTrainingDay ? trainingDayPlan(from: prefs) : restDayPlan(from: prefs)
        }
        return trainingDayPlan(from: prefs)
    }

    static func trainingDayPlan(from prefs: WorkoutPlanPreferences) -> DailyNutritionPlan {
        DailyNutritionPlan(
            caloriesKcal: prefs.dailyCalorieTargetKcal,
            proteinGrams: prefs.dailyProteinGrams,
            carbGrams: prefs.dailyCarbGrams,
            fatGrams: prefs.dailyFatGrams,
            notes: prefs.nutritionNotes
        )
    }

    static func restDayPlan(from prefs: WorkoutPlanPreferences) -> DailyNutritionPlan {
        DailyNutritionPlan(
            caloriesKcal: prefs.restDayCalorieTargetKcal,
            proteinGrams: prefs.restDayProteinGrams,
            carbGrams: prefs.restDayCarbGrams,
            fatGrams: prefs.restDayFatGrams,
            notes: prefs.restDayNotes
        )
    }

    static func dayTypeLabel(isTrainingDay: Bool) -> String {
        isTrainingDay ? "训练日" : "休息日"
    }

    /// 相对减脂基准预算的微调说明（如「+80 kcal」）
    static func calorieDeltaLabel(effective: Double, baseline: Double?) -> String? {
        guard let baseline, baseline > 0 else { return nil }
        let delta = Int((effective - baseline).rounded())
        if abs(delta) < 5 { return "与减脂建议一致" }
        return delta > 0 ? "+\(delta) kcal" : "\(delta) kcal"
    }

    /// 首页营养条副标题：突出「微调」而非训练/休息双列
    static func todayNutritionSubtitle(
        source: String?,
        isTrainingDay: Bool,
        effectiveCalories: Double,
        baselineCalories: Double?
    ) -> String? {
        guard let source, !source.isEmpty else { return nil }
        let day = dayTypeLabel(isTrainingDay: isTrainingDay)
        if let delta = calorieDeltaLabel(effective: effectiveCalories, baseline: baselineCalories) {
            return "训练计划微调 · \(day) · 较减脂建议 \(delta)"
        }
        return "\(planSourceLabel(source)) · \(day)"
    }

    /// Calendar.weekday 英文短标签（Mon–Sun）
    static func weekdayEnglishShort(for dayOfWeek: Int) -> String {
        switch dayOfWeek {
        case 1: return "Sun"
        case 2: return "Mon"
        case 3: return "Tue"
        case 4: return "Wed"
        case 5: return "Thu"
        case 6: return "Fri"
        case 7: return "Sat"
        default: return "?"
        }
    }

    /// 在 weekStart（周一）起的自然周内，定位指定 weekday 的日期
    static func dateInWeek(weekStart: Date, weekday: Int, calendar: Calendar = .current) -> Date? {
        for offset in 0..<7 {
            guard let dayDate = calendar.date(byAdding: .day, value: offset, to: weekStart) else { continue }
            if calendar.component(.weekday, from: dayDate) == weekday {
                return dayDate
            }
        }
        return nil
    }

    /// 与「本周安排」对齐：仅返回有排课的训练日营养目标（周一→周日序）
    static func scheduleAlignedNutritionDays(
        prefs: WorkoutPlanPreferences,
        trainingWeekdays: [Int],
        weekStart: Date,
        baselineCalories: Double? = nil,
        referenceDate: Date = Date()
    ) -> [WeeklyNutritionDay] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: referenceDate)
        let ordered = trainingWeekdays.sorted {
            WorkoutPlanEntry.mondayFirstSortOrder(for: $0) < WorkoutPlanEntry.mondayFirstSortOrder(for: $1)
        }

        return ordered.compactMap { weekday -> WeeklyNutritionDay? in
            guard let dayDate = dateInWeek(weekStart: weekStart, weekday: weekday, calendar: calendar) else {
                return nil
            }
            let plan = effectivePlan(prefs, isTrainingDay: true)
            let delta: Int? = {
                guard let baselineCalories, baselineCalories > 0 else { return nil }
                let value = Int((plan.caloriesKcal - baselineCalories).rounded())
                return abs(value) >= 5 ? value : nil
            }()
            return WeeklyNutritionDay(
                id: dayDate,
                weekdayShort: weekdayEnglishShort(for: weekday),
                isTrainingDay: true,
                plan: plan,
                calorieDeltaFromBaseline: delta,
                isToday: calendar.isDate(dayDate, inSameDayAs: today)
            )
        }
    }

    /// 非排课日的统一休息日营养摘要
    static func restDayNutritionSummary(
        prefs: WorkoutPlanPreferences,
        trainingWeekdays: [Int]
    ) -> (count: Int, calories: Int)? {
        guard hasSplitPlan(prefs) else { return nil }
        let restCount = max(7 - trainingWeekdays.count, 0)
        guard restCount > 0 else { return nil }
        let rest = restDayPlan(from: prefs)
        return (restCount, Int(rest.caloriesKcal.rounded()))
    }

    /// 生成本周 7 日营养目标（Mon–Sun；有排课日为训练方案，其余为休息方案）
    static func weeklyNutritionDays(
        prefs: WorkoutPlanPreferences,
        trainingWeekdays: [Int],
        weekStart: Date,
        baselineCalories: Double? = nil,
        referenceDate: Date = Date()
    ) -> [WeeklyNutritionDay] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: referenceDate)
        let trainingSet = Set(trainingWeekdays)

        return (0..<7).compactMap { offset -> WeeklyNutritionDay? in
            guard let dayDate = calendar.date(byAdding: .day, value: offset, to: weekStart) else { return nil }
            let weekday = calendar.component(.weekday, from: dayDate)
            let isTraining = trainingSet.contains(weekday)
            let plan = effectivePlan(prefs, isTrainingDay: isTraining)
            let delta: Int? = {
                guard let baselineCalories, baselineCalories > 0 else { return nil }
                let value = Int((plan.caloriesKcal - baselineCalories).rounded())
                return abs(value) >= 5 ? value : nil
            }()
            return WeeklyNutritionDay(
                id: dayDate,
                weekdayShort: weekdayEnglishShort(for: weekday),
                isTrainingDay: isTraining,
                plan: plan,
                calorieDeltaFromBaseline: delta,
                isToday: calendar.isDate(dayDate, inSameDayAs: today)
            )
        }
    }

    /// 兼容：从本周安排条目推导 training weekdays
    static func weeklyNutritionDays(
        prefs: WorkoutPlanPreferences,
        weekEntries: [WorkoutPlanEntry],
        weekStart: Date,
        baselineCalories: Double? = nil,
        referenceDate: Date = Date()
    ) -> [WeeklyNutritionDay] {
        weeklyNutritionDays(
            prefs: prefs,
            trainingWeekdays: weekEntries.map(\.dayOfWeek),
            weekStart: weekStart,
            baselineCalories: baselineCalories,
            referenceDate: referenceDate
        )
    }

    /// 今日摄入超出预算时，估算需追加的中等强度运动时长
    static func surplusHint(
        consumed: Double,
        budget: Double,
        kcalPerMinute: Double = 6.5
    ) -> SurplusExerciseHint? {
        let surplus = consumed - budget
        guard surplus > 30 else { return nil }
        let rate = max(kcalPerMinute, 4)
        let minutes = Int(ceil(surplus / rate))
        let message = "今日已超出预算约 \(Int(surplus)) kcal，建议追加约 \(minutes) 分钟中等强度有氧（快走/椭圆等，约 \(Int(Double(minutes) * rate)) kcal）。"
        return SurplusExerciseHint(surplusKcal: surplus, suggestedMinutes: minutes, message: message)
    }

    static func planSourceLabel(_ source: String) -> String {
        switch source {
        case "ai": return "AI 训练计划营养"
        case "engine": return "智能训练计划营养"
        default: return "减脂计划"
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
