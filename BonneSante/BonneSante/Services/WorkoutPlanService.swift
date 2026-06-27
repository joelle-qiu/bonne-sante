import Foundation
import SwiftData

/// 训练计划持久化、HealthKit 完成度同步、待办提醒
/// @author jiali.qiu
enum WorkoutPlanService {

    struct WeekProgress: Equatable {
        var completedSessions: Int
        var totalSessions: Int
        var completedMinutes: Int
        var plannedMinutes: Int
        var watchMatchedSessions: Int
    }

    /// 本周一 00:00（本地时区）
    static func startOfWeek(_ date: Date = Date()) -> Date {
        let calendar = Calendar.current
        let weekday = calendar.component(.weekday, from: date)
        let daysFromMonday = (weekday + 5) % 7
        return calendar.date(byAdding: .day, value: -daysFromMonday, to: calendar.startOfDay(for: date))
            ?? calendar.startOfDay(for: date)
    }

    static func endOfWeek(from weekStart: Date) -> Date {
        Calendar.current.date(byAdding: .day, value: 7, to: weekStart) ?? weekStart
    }

    static func loadOrCreatePreferences(modelContext: ModelContext) -> WorkoutPlanPreferences {
        let descriptor = FetchDescriptor<WorkoutPlanPreferences>()
        if let existing = try? modelContext.fetch(descriptor).first {
            return existing
        }
        let prefs = WorkoutPlanPreferences()
        modelContext.insert(prefs)
        try? modelContext.save()
        return prefs
    }

    /// 首次授权后根据 Apple 健康近 90 天锻炼历史推断 planType / sessionsPerWeek（仅执行一次）
    @MainActor
    static func inferPreferencesFromHealthKitIfNeeded(
        healthKit: HealthKitService,
        modelContext: ModelContext
    ) async -> Bool {
        let prefs = loadOrCreatePreferences(modelContext: modelContext)
        guard !prefs.inferredFromHealthKit else { return false }
        guard healthKit.isHealthKitAvailable else { return false }

        let history = await healthKit.fetchWorkoutHistory(days: 90)
        let result = WorkoutPreferenceInferencer.infer(from: history)

        prefs.healthKitWorkoutSummaryText = result.summaryText
        if result.hadEnoughData {
            prefs.planType = result.planType
            prefs.sessionsPerWeek = result.sessionsPerWeek
        } else if !history.isEmpty {
            prefs.sessionsPerWeek = result.sessionsPerWeek
        }
        prefs.inferredFromHealthKit = true
        prefs.updatedAt = Date()
        try? modelContext.save()
        return result.hadEnoughData
    }

    static func entriesForWeek(_ weekStart: Date, modelContext: ModelContext) -> [WorkoutPlanEntry] {
        let end = endOfWeek(from: weekStart)
        let descriptor = FetchDescriptor<WorkoutPlanEntry>(
            predicate: #Predicate<WorkoutPlanEntry> { entry in
                entry.weekStartDate >= weekStart && entry.weekStartDate < end
            },
            sortBy: [SortDescriptor(\.dayOfWeek), SortDescriptor(\.createdAt)]
        )
        return WorkoutPlanEntry.sortedMondayFirst((try? modelContext.fetch(descriptor)) ?? [])
    }

    /// 与日期区间重叠的周训练计划
    static func entries(from start: Date, to end: Date, modelContext: ModelContext) -> [WorkoutPlanEntry] {
        let rangeStart = startOfWeek(start)
        let descriptor = FetchDescriptor<WorkoutPlanEntry>(
            predicate: #Predicate<WorkoutPlanEntry> { entry in
                entry.weekStartDate >= rangeStart && entry.weekStartDate < end
            },
            sortBy: [SortDescriptor(\.weekStartDate), SortDescriptor(\.createdAt)]
        )
        return WorkoutPlanEntry.sortedMondayFirst((try? modelContext.fetch(descriptor)) ?? [])
    }

    static func sessionDate(for entry: WorkoutPlanEntry) -> Date? {
        dateForEntry(entry, weekStart: entry.weekStartDate)
    }

    /// 今日是否在本周训练计划中有排课
    static func hasPlannedSession(on date: Date = Date(), modelContext: ModelContext) -> Bool {
        let weekStart = startOfWeek(date)
        let entries = entriesForWeek(weekStart, modelContext: modelContext)
        let calendar = Calendar.current
        return entries.contains { entry in
            guard let sessionDate = sessionDate(for: entry) else { return false }
            return calendar.isDate(sessionDate, inSameDayAs: date)
        }
    }

    /// 保存引擎/AI 输出并同步训练待办
    @discardableResult
    static func savePlan(
        _ output: WorkoutPlanEngine.Output,
        phase: CyclePhase,
        source: String,
        weekStart: Date,
        modelContext: ModelContext
    ) throws -> [WorkoutPlanEntry] {
        let existing = entriesForWeek(weekStart, modelContext: modelContext)
        for item in existing {
            deleteWorkoutReminderTodo(for: item.id, modelContext: modelContext)
            deleteExercises(for: item.id, modelContext: modelContext)
            modelContext.delete(item)
        }

        var saved: [WorkoutPlanEntry] = []
        for session in output.sessions {
            let entry = WorkoutPlanEntry(
                dayOfWeek: session.dayOfWeek,
                workoutType: session.workoutType,
                targetMinutes: session.targetMinutes,
                intensity: session.intensity,
                cyclePhase: phase.rawValue,
                weekStartDate: weekStart,
                notes: session.notes,
                moodReminderText: session.moodReminder,
                targetCalories: session.targetCalories,
                source: source
            )
            modelContext.insert(entry)
            saved.append(entry)
            insertExercises(session.exercises, sessionId: entry.id, modelContext: modelContext)
        }

        WorkoutMorningReminderService.sync(modelContext: modelContext)

        let prefs = loadOrCreatePreferences(modelContext: modelContext)
        prefs.sessionsPerWeek = output.sessions.count
        prefs.dietAdviceText = output.dietAdvice
        prefs.weeklySummaryText = output.weeklySummary
        prefs.lastGeneratedSource = source
        prefs.weekStartDate = weekStart
        prefs.weeklyBurnGoalKcal = output.weeklyBurnGoalKcal
        WorkoutNutritionPlanner.apply(output.splitNutrition, source: source, to: prefs)
        prefs.updatedAt = Date()

        try modelContext.save()
        return saved
    }

    static func exercises(for sessionId: UUID, modelContext: ModelContext) -> [WorkoutExercise] {
        let descriptor = FetchDescriptor<WorkoutExercise>(
            predicate: #Predicate<WorkoutExercise> { $0.sessionId == sessionId },
            sortBy: [SortDescriptor(\.sortOrder), SortDescriptor(\.createdAt)]
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    static func completedCalories(for exercises: [WorkoutExercise]) -> Double {
        exercises.reduce(0) { partial, ex in
            guard ex.sets > 0 else { return partial + (ex.isFullyCompleted ? ex.targetCalories : 0) }
            let ratio = Double(min(ex.completedSets, ex.sets)) / Double(ex.sets)
            return partial + ex.targetCalories * ratio
        }
    }

    /// 动作组数完成度（组勾选仅用于次数/完成度，不参与消耗计算）
    struct SetProgress: Equatable {
        var completedSets: Int
        var totalSets: Int
        var fraction: Double
        /// ≥65% 组数视为本场训练完成
        var isSessionComplete: Bool
    }

    static func setProgress(for exercises: [WorkoutExercise]) -> SetProgress {
        let total = exercises.reduce(0) { $0 + max($1.sets, 1) }
        let completed = exercises.reduce(0) { $0 + min($1.completedSets, max($1.sets, 1)) }
        let fraction = total > 0 ? Double(completed) / Double(total) : 0
        return SetProgress(
            completedSets: completed,
            totalSets: total,
            fraction: fraction,
            isSessionComplete: fraction >= 0.65
        )
    }

    /// 训练日当天 Apple 健康活动消耗（优先当日总活动，辅以锻炼记录）
    static func watchActiveKcal(
        for entry: WorkoutPlanEntry,
        energyProfile: EnergyProfileSnapshot,
        workouts: [WorkoutSnapshot]
    ) -> Double {
        guard let sessionDate = sessionDate(for: entry) else { return 0 }
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: sessionDate)
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart

        if calendar.isDateInToday(sessionDate), energyProfile.todayActiveKcal > 0 {
            return energyProfile.todayActiveKcal
        }

        let workoutSum = workouts
            .filter { $0.date >= dayStart && $0.date < dayEnd }
            .reduce(0.0) { $0 + $1.activeCalories }
        if workoutSum > 0 { return workoutSum }

        return 0
    }

    /// 换动作：拉取 AI 候选（2–3 个）
    @MainActor
    static func fetchSwapCandidates(
        exercise: WorkoutExercise,
        entry: WorkoutPlanEntry,
        reason: String,
        preferences: WorkoutPlanPreferences,
        modelContext: ModelContext
    ) async throws -> WorkoutPlanAIService.SwapCandidatesResult {
        let allExercises = exercises(for: entry.id, modelContext: modelContext)
        let summary = WorkoutPlanPrompt.sessionSummary(entry: entry, exercises: allExercises)
        return try await WorkoutPlanAIService.fetchSwapCandidates(
            sessionSummary: summary,
            exerciseName: exercise.name,
            reason: reason,
            excluded: preferences.excludedExercises
        )
    }

    /// 应用用户选中的替代动作
    @MainActor
    static func applySelectedSwap(
        exercise: WorkoutExercise,
        entry: WorkoutPlanEntry,
        selected: WorkoutPlanEngine.PlannedExercise,
        candidates: WorkoutPlanAIService.SwapCandidatesResult,
        reason: String,
        preferences: WorkoutPlanPreferences,
        modelContext: ModelContext
    ) throws {
        let original = exercise.originalName.isEmpty ? exercise.name : exercise.originalName
        exercise.originalName = original
        exercise.name = selected.name
        exercise.muscleGroup = selected.muscleGroup
        exercise.equipment = selected.equipment
        exercise.sets = selected.sets
        exercise.reps = selected.reps
        exercise.restSeconds = selected.restSeconds
        exercise.targetCalories = selected.targetCalories
        exercise.notes = selected.notes
        exercise.exerciseKind = selected.exerciseKind
        exercise.swapReason = reason
        exercise.completedSets = 0

        entry.targetCalories = candidates.sessionTargetCalories
        entry.targetMinutes = candidates.sessionTargetMinutes
        entry.replanNote = candidates.replanNote

        if candidates.addToExcludedList {
            preferences.appendExcludedExercise(original)
        }
        preferences.updatedAt = Date()
        try modelContext.save()
    }

    /// 换动作并由 AI 重新评估本场（自动选第一个候选，兼容旧流程）
    @MainActor
    static func applyExerciseSwap(
        exercise: WorkoutExercise,
        entry: WorkoutPlanEntry,
        reason: String,
        preferences: WorkoutPlanPreferences,
        modelContext: ModelContext
    ) async throws {
        let candidates = try await fetchSwapCandidates(
            exercise: exercise,
            entry: entry,
            reason: reason,
            preferences: preferences,
            modelContext: modelContext
        )
        guard let first = candidates.alternatives.first else { return }
        try applySelectedSwap(
            exercise: exercise,
            entry: entry,
            selected: first,
            candidates: candidates,
            reason: reason,
            preferences: preferences,
            modelContext: modelContext
        )
    }

    static func weeklyCompletedBurn(
        entries: [WorkoutPlanEntry],
        modelContext: ModelContext
    ) -> Double {
        entries.reduce(0) { partial, entry in
            let exs = exercises(for: entry.id, modelContext: modelContext)
            return partial + completedCalories(for: exs)
        }
    }

    static func weeklyPlannedBurn(entries: [WorkoutPlanEntry]) -> Double {
        entries.reduce(0) { $0 + $1.targetCalories }
    }

    /// 本周消耗完成值：仅 Apple 健康活动消耗（不回退计划勾选）
    static func weeklyBurnCompleted(
        energyProfile: EnergyProfileSnapshot,
        entries: [WorkoutPlanEntry],
        modelContext: ModelContext
    ) -> (value: Double, usesHealthData: Bool) {
        _ = entries
        _ = modelContext
        guard energyProfile.hasWatchData else {
            return (0, false)
        }
        return (energyProfile.weekActiveKcal, true)
    }

    /// 本周消耗目标：有 Watch 时用 7 日活动均值 × 排课天数，否则用计划值
    static func weeklyBurnGoal(
        energyProfile: EnergyProfileSnapshot,
        trainingDays: Int,
        storedGoal: Double,
        plannedBurn: Double
    ) -> (value: Double, usesHealthData: Bool) {
        if let avg = energyProfile.avgActiveKcal7d, avg > 0, energyProfile.hasWatchData {
            let days = max(trainingDays, 1)
            return (avg * Double(days), true)
        }
        if storedGoal > 0 { return (storedGoal, false) }
        return (plannedBurn, false)
    }

    static func incrementCompletedSets(_ exercise: WorkoutExercise, modelContext: ModelContext) {
        if exercise.completedSets < exercise.sets {
            exercise.completedSets += 1
        }
        try? modelContext.save()
    }

    static func decrementCompletedSets(_ exercise: WorkoutExercise, modelContext: ModelContext) {
        if exercise.completedSets > 0 {
            exercise.completedSets -= 1
        }
        try? modelContext.save()
    }

    /// 将 AI 教练输出的计划写入本场训练（替换动作清单）
    @MainActor
    static func applyCoachSessionPlan(
        entry: WorkoutPlanEntry,
        plan: CoachSessionPlan,
        modelContext: ModelContext
    ) throws {
        guard !plan.exercises.isEmpty else {
            throw AIServiceError.parsingError("计划中没有动作")
        }
        deleteExercises(for: entry.id, modelContext: modelContext)
        insertExercises(plan.exercises, sessionId: entry.id, modelContext: modelContext)

        if let type = plan.workoutType, !type.isEmpty {
            entry.workoutType = type
        }
        entry.targetMinutes = plan.sessionTargetMinutes
        entry.targetCalories = plan.sessionTargetCalories
        entry.replanNote = plan.replanNote
        entry.source = "ai"
        entry.isCompleted = false
        entry.completedAt = nil
        try modelContext.save()
    }

    private static func insertExercises(
        _ planned: [WorkoutPlanEngine.PlannedExercise],
        sessionId: UUID,
        modelContext: ModelContext
    ) {
        for (index, item) in planned.enumerated() {
            let ex = WorkoutExercise(
                sessionId: sessionId,
                sortOrder: index,
                name: item.name,
                muscleGroup: item.muscleGroup,
                equipment: item.equipment,
                sets: item.sets,
                reps: item.reps,
                restSeconds: item.restSeconds,
                targetCalories: item.targetCalories,
                notes: item.notes,
                exerciseKind: item.exerciseKind
            )
            modelContext.insert(ex)
        }
    }

    private static func deleteExercises(for sessionId: UUID, modelContext: ModelContext) {
        let items = exercises(for: sessionId, modelContext: modelContext)
        for item in items {
            modelContext.delete(item)
        }
    }

    @MainActor
    static func buildEngineInput(
        preferences: WorkoutPlanPreferences,
        healthContext: UnifiedHealthContext?,
        userGoal: UserGoal?,
        currentWeight: Double?,
        recentWorkouts: [WorkoutSnapshot],
        profileNickname: String = ""
    ) -> WorkoutPlanEngine.Input {
        let phaseInfo = healthContext?.cyclePhaseInfo ?? CycleEngine.phaseInfo(from: nil)
        let minutes7d = Int(recentWorkouts.reduce(0) { $0 + $1.durationMinutes })
        let healthNotes = healthContext?.healthSummary?.dietaryNotes ?? []
        let risks = (healthContext?.activeRiskFlags ?? []).prefix(3).map {
            "\($0.metricName) \($0.currentValue)"
        }
        let activityLevel = healthContext?.intelligenceProfile?.calibratedActivity
            ?? userGoal?.activityLevel
            ?? "light"

        return WorkoutPlanEngine.Input(
            phase: phaseInfo.phase,
            cycleDay: phaseInfo.cycleDay,
            sessionsPerWeek: preferences.sessionsPerWeek,
            currentWeight: currentWeight,
            targetWeight: userGoal?.targetWeight,
            activityLevel: activityLevel,
            dailyCalorieBudget: healthContext?.dailyCalorieBudget,
            proteinTargetGrams: healthContext?.macroTargets?.proteinGrams,
            recentWorkoutMinutes7d: minutes7d,
            recentWorkoutCount7d: recentWorkouts.count,
            healthDietNotes: healthNotes,
            riskHints: Array(risks),
            cycleWorkoutTip: phaseInfo.workoutTip,
            dailyDeficitTarget: healthContext?.dailyDeficit,
            planType: preferences.planType,
            planStyle: preferences.planStyle,
            moodDayOverrides: preferences.moodDayOverrides,
            moodPinnedWeekdays: preferences.moodPinnedWeekdays,
            profileNickname: profileNickname
        )
    }

    @MainActor
    static func buildAIContext(
        preferences: WorkoutPlanPreferences,
        healthContext: UnifiedHealthContext?,
        userGoal: UserGoal?,
        currentWeight: Double?,
        recentWorkouts: [WorkoutSnapshot],
        weatherSnapshot: WeeklyWeatherSnapshot? = nil,
        profileNickname: String = ""
    ) -> String {
        let phaseInfo = healthContext?.cyclePhaseInfo ?? CycleEngine.phaseInfo(from: nil)
        var workoutLines: [String] = []
        for item in recentWorkouts.prefix(8) {
            let formatter = DateFormatter()
            formatter.dateFormat = "M/d"
            workoutLines.append("\(formatter.string(from: item.date)) \(item.activityLabel) \(Int(item.durationMinutes))min")
        }

        let healthSummary = healthContext?.healthSummary?.headline ?? ""
        let risks = (healthContext?.activeRiskFlags ?? []).prefix(4).map {
            "· \($0.metricName) \($0.currentValue) — \($0.suggestedAction)"
        }.joined(separator: "\n")

        var macroSummary = ""
        if let targets = healthContext?.macroTargets {
            macroSummary = "蛋白 \(Int(targets.proteinGrams))g · 碳水 \(Int(targets.carbGrams))g · 脂肪 \(Int(targets.fatGrams))g"
        }

        var personalizationSummary = ""
        if let intel = healthContext?.intelligenceProfile {
            personalizationSummary = HealthIntelligenceEngine.formatForWorkoutAI(
                profile: intel,
                healthSummary: healthContext?.healthSummary,
                habitSummary: preferences.healthKitWorkoutSummaryText,
                targetBodyFat: userGoal?.targetBodyFat,
                targetLeanMassKg: userGoal?.effectiveTargetLeanMassKg
            )
        }

        var weatherSummary = ""
        if preferences.planStyle == .moodWeather {
            let planned = MoodWorkoutScheduler.schedule(
                sessionsCount: preferences.sessionsPerWeek,
                weather: weatherSnapshot,
                overrides: preferences.moodDayOverrides,
                pinnedWeekdays: preferences.moodPinnedWeekdays
            )
            weatherSummary = MoodWorkoutScheduler.formatScheduleForAI(
                sessions: planned,
                sessionsCount: preferences.sessionsPerWeek,
                weather: weatherSnapshot,
                overrides: preferences.moodDayOverrides
            )
        } else if preferences.planType.usesWeatherScheduling, let weather = weatherSnapshot, weather.isValid {
            weatherSummary = weather.formatForWorkoutAI(
                sessionsNeeded: preferences.sessionsPerWeek,
                activityLabel: preferences.planType.label
            )
        }

        return WorkoutPlanPrompt.buildContext(
            phase: phaseInfo.phase,
            cycleDay: phaseInfo.cycleDay,
            goal: userGoal,
            currentWeight: currentWeight,
            dailyBudget: healthContext?.dailyCalorieBudget,
            dailyDeficit: healthContext?.dailyDeficit,
            proteinTarget: healthContext?.macroTargets?.proteinGrams,
            macroSummary: macroSummary,
            recentWorkouts: workoutLines.joined(separator: "\n"),
            healthSummary: healthSummary,
            riskHints: risks,
            cycleTips: phaseInfo.workoutTip,
            planType: preferences.planType,
            planStyle: preferences.planStyle,
            healthKitHabitSummary: preferences.healthKitWorkoutSummaryText,
            personalizationSummary: personalizationSummary,
            weatherSummary: weatherSummary,
            profileNickname: profileNickname
        )
    }

    /// 根据 HealthKit 锻炼记录自动标记完成
    static func syncCompletionFromHealthKit(
        entries: [WorkoutPlanEntry],
        workouts: [WorkoutSnapshot],
        weekStart: Date,
        modelContext: ModelContext
    ) {
        guard !entries.isEmpty else { return }
        var changed = false
        let calendar = Calendar.current

        for entry in entries where !entry.isCompleted {
            guard let sessionDate = dateForEntry(entry, weekStart: weekStart) else { continue }
            let dayStart = calendar.startOfDay(for: sessionDate)
            let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart

            let dayWorkouts = workouts.filter { $0.date >= dayStart && $0.date < dayEnd }
            let totalMinutes = dayWorkouts.reduce(0.0) { $0 + $1.durationMinutes }
            let threshold = Double(entry.targetMinutes) * 0.65

            if totalMinutes >= threshold {
                entry.isCompleted = true
                entry.completedAt = dayWorkouts.last?.date ?? Date()
                changed = true
            }
        }

        if changed {
            try? modelContext.save()
        }
    }

    static func weekProgress(
        entries: [WorkoutPlanEntry],
        exercisesBySession: [UUID: [WorkoutExercise]],
        workouts: [WorkoutSnapshot],
        weekStart: Date
    ) -> WeekProgress {
        let plannedMinutes = entries.reduce(0) { $0 + $1.targetMinutes }

        let setCompletedEntries = entries.filter { entry in
            let exs = exercisesBySession[entry.id] ?? []
            return setProgress(for: exs).isSessionComplete
        }
        let completedMinutes = setCompletedEntries.reduce(0) { $0 + $1.targetMinutes }

        let calendar = Calendar.current
        let watchMatched = entries.filter { entry in
            guard let sessionDate = dateForEntry(entry, weekStart: weekStart) else { return false }
            let dayStart = calendar.startOfDay(for: sessionDate)
            let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart
            let minutes = workouts.filter { $0.date >= dayStart && $0.date < dayEnd }
                .reduce(0.0) { $0 + $1.durationMinutes }
            return minutes >= Double(entry.targetMinutes) * 0.65
        }.count

        return WeekProgress(
            completedSessions: setCompletedEntries.count,
            totalSessions: entries.count,
            completedMinutes: completedMinutes,
            plannedMinutes: plannedMinutes,
            watchMatchedSessions: watchMatched
        )
    }

    static func toggleCompleted(_ entry: WorkoutPlanEntry, modelContext: ModelContext) {
        entry.isCompleted.toggle()
        entry.completedAt = entry.isCompleted ? Date() : nil
        try? modelContext.save()
        WorkoutMorningReminderService.sync(modelContext: modelContext)
    }

    /// 单场切换训练侧重（如肩背日改为臀腿），仅替换本场动作
    static func applySessionFocus(
        _ entry: WorkoutPlanEntry,
        focus: WorkoutSessionFocus,
        modelContext: ModelContext
    ) {
        let phase = CyclePhase(rawValue: entry.cyclePhase) ?? .unknown
        let planned = WorkoutPlanEngine.exercisesForFocus(
            focus,
            minutes: entry.targetMinutes,
            intensity: entry.intensity,
            phase: phase
        )
        deleteExercises(for: entry.id, modelContext: modelContext)
        insertExercises(planned, sessionId: entry.id, modelContext: modelContext)
        entry.workoutType = focus.displayWorkoutType
        entry.targetCalories = planned.reduce(0) { $0 + $1.targetCalories }
        entry.notes = "已调整为\(focus.label)"
        entry.replanNote = ""
        try? modelContext.save()
    }

    /// 将训练日改到其他 weekday；若目标日已有安排则与对调
    static func rescheduleEntry(
        _ entry: WorkoutPlanEntry,
        toDayOfWeek newDay: Int,
        weekEntries: [WorkoutPlanEntry],
        weekStart: Date,
        modelContext: ModelContext
    ) {
        guard (1...7).contains(newDay), newDay != entry.dayOfWeek else { return }

        if let other = weekEntries.first(where: { $0.id != entry.id && $0.dayOfWeek == newDay }) {
            let previousDay = entry.dayOfWeek
            entry.dayOfWeek = newDay
            other.dayOfWeek = previousDay
        } else {
            entry.dayOfWeek = newDay
        }

        WorkoutMorningReminderService.sync(modelContext: modelContext)
        try? modelContext.save()
    }

    // MARK: - Private

    private static func dateForEntry(_ entry: WorkoutPlanEntry, weekStart: Date) -> Date? {
        let calendar = Calendar.current
        for offset in 0..<7 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: weekStart) else { continue }
            if calendar.component(.weekday, from: day) == entry.dayOfWeek {
                return day
            }
        }
        return nil
    }

    private static func deleteWorkoutReminderTodo(for entryId: UUID, modelContext: ModelContext) {
        let entryIdString = entryId.uuidString
        let descriptor = FetchDescriptor<TodoItem>(
            predicate: #Predicate<TodoItem> { $0.seriesKey == entryIdString }
        )
        guard let todos = try? modelContext.fetch(descriptor) else { return }
        for todo in todos {
            TodoService.cancelNotifications(for: todo.id)
            modelContext.delete(todo)
        }
    }
}
