import SwiftUI
import SwiftData

/// 周训练计划：规则引擎 + DeepSeek AI + HealthKit 完成度
/// @author jiali.qiu
struct WorkoutPlanView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.healthContext) private var healthContext
    @Environment(\.colorScheme) private var colorScheme

    @Query private var preferencesList: [WorkoutPlanPreferences]
    @Query private var settingsList: [UserSettings]
    @Query private var goals: [UserGoal]
    @Query(sort: \WeightEntry.date, order: .reverse) private var weightEntries: [WeightEntry]
    @Query(sort: \FoodEntry.createdAt, order: .reverse) private var foodEntries: [FoodEntry]
    @Query private var cycleProfiles: [CycleProfile]

    @State private var weekEntries: [WorkoutPlanEntry] = []
    @State private var exercisesBySession: [UUID: [WorkoutExercise]] = [:]
    @State private var weeklyNutritionDaysCache: [WorkoutNutritionPlanner.WeeklyNutritionDay] = []
    @State private var isLoadingWeek = false
    @State private var isGenerating = false
    @State private var errorMessage: String?
    @State private var showAPIKeySetup = false
    @StateObject private var locationService = LocationService()
    @State private var weatherSnapshot: WeeklyWeatherSnapshot = .empty
    @State private var isLoadingWeather = false
    @State private var moodDayOverrides: [Int: WorkoutPlanType] = [:]
    @State private var moodPinnedWeekdays: [Int]?
    @State private var planConfigExpanded: Bool?

    private var weekStart: Date { WorkoutPlanService.startOfWeek() }
    private var preferences: WorkoutPlanPreferences {
        preferencesList.first ?? WorkoutPlanPreferences()
    }

    private var currentWeight: Double? {
        healthContext?.currentWeight ?? weightEntries.first?.weight
    }

    private var phaseInfo: CycleEngine.PhaseInfo {
        healthContext?.cyclePhaseInfo ?? CycleEngine.phaseInfo(from: cycleProfiles.first)
    }

    private var progress: WorkoutPlanService.WeekProgress {
        WorkoutPlanService.weekProgress(
            entries: weekEntries,
            exercisesBySession: exercisesBySession,
            workouts: healthContext?.healthKitService.recentWorkouts ?? [],
            weekStart: weekStart
        )
    }

    private var weekEnd: Date { WorkoutPlanService.endOfWeek(from: weekStart) }

    private var weeklyBurnGoalInfo: (value: Double, usesHealthData: Bool) {
        let planned = WorkoutPlanService.weeklyPlannedBurn(entries: weekEntries)
        return WorkoutPlanService.weeklyBurnGoal(
            plannedBurn: planned,
            storedGoal: preferences.weeklyBurnGoalKcal
        )
    }

    private var weeklyBurnGoal: Double { weeklyBurnGoalInfo.value }

    private var weeklyBurnUsesHealthData: Bool { weeklyBurnGoalInfo.usesHealthData }

    private var weeklyBurnCompletedInfo: (value: Double, usesHealthData: Bool) {
        return WorkoutPlanService.weeklyBurnCompleted(
            workouts: healthContext?.healthKitService.recentWorkouts ?? [],
            weekStart: weekStart,
            weekEnd: weekEnd,
            entries: weekEntries,
            exercisesBySession: exercisesBySession,
            modelContext: modelContext
        )
    }

    private var weeklyBurnCompleted: Double { weeklyBurnCompletedInfo.value }

    private var burnProgressFraction: Double {
        guard weeklyBurnGoal > 0 else { return 0 }
        return min(weeklyBurnCompleted / weeklyBurnGoal, 1)
    }

    private var weeklyNutritionDays: [WorkoutNutritionPlanner.WeeklyNutritionDay] {
        weeklyNutritionDaysCache
    }

    /// 与营养条同步的有效训练 weekday：已生成用「本周安排」，预览阶段用排课预览
    private var effectiveTrainingWeekdays: [Int] {
        if !weekEntries.isEmpty {
            return WorkoutPlanEntry.sortedMondayFirst(weekEntries).map(\.dayOfWeek)
        }
        if selectedPlanStyle == .moodWeather {
            return moodScheduledSessions
                .map(\.dayOfWeek)
                .sorted {
                    WorkoutPlanEntry.mondayFirstSortOrder(for: $0)
                        < WorkoutPlanEntry.mondayFirstSortOrder(for: $1)
                }
        }
        return []
    }

    private var scheduleNutritionCaption: String? {
        let weekdays = trainingWeekdaysForNutrition
        guard !weekdays.isEmpty else { return nil }
        let labels = weekdays.map { WorkoutNutritionPlanner.weekdayEnglishShort(for: $0) }
        return "与 \(weekdays.count) 场排课同步（\(labels.joined(separator: ", "))）"
    }

    /// 营养条训练日来源：已生成用「本周安排」，预览阶段用排课预览
    private var trainingWeekdaysForNutrition: [Int] {
        if !weekEntries.isEmpty {
            return weekEntries.map(\.dayOfWeek)
        }
        return effectiveTrainingWeekdays
    }

    private var todayEntry: WorkoutPlanEntry? {
        let calendar = Calendar.current
        return weekEntries.first { entry in
            guard let sessionDate = WorkoutPlanService.sessionDate(for: entry) else { return false }
            return calendar.isDateInToday(sessionDate)
        }
    }

    private var healthProfileSummary: String {
        healthContext?.advisorContextSummary() ?? "暂无健康档案数据"
    }

    private var genderLabel: String? {
        goals.first?.genderDisplayLabel
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                phaseHeader
                planConfigSection
                weeklyNutritionCard
                progressCard
                planCoachSection
                planOutputCard
                scheduleSection
                watchHistorySection
                disclaimer
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Theme.horizontalPadding)
            .padding(.vertical, 16)
        }
        .cycleThemedPageBackground()
        .navigationTitle("训练计划")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: weekStart) {
            loadMoodOverridesFromPreferences()
            await loadWeek()
        }
        .refreshable { await loadWeek(force: true) }
        .alert("提示", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("好的", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
        .sheet(isPresented: $showAPIKeySetup) {
            NavigationStack {
                AISettingsView()
            }
        }
    }

    // MARK: - Sections

    private var phaseHeader: some View {
        HStack(spacing: 12) {
            Image(systemName: "figure.run")
                .font(.title2)
                .foregroundStyle(Theme.adaptiveAccent(colorScheme))
            VStack(alignment: .leading, spacing: 4) {
                Text(phaseInfo.label)
                    .font(.headline)
                    .foregroundStyle(Theme.adaptiveTextPrimary(colorScheme))
                Text(phaseInfo.workoutTip)
                    .font(.caption)
                    .foregroundStyle(Theme.adaptiveTextSecondary(colorScheme))
            }
            Spacer()
        }
        .morandiCard()
    }

    @ViewBuilder
    private var weeklyNutritionCard: some View {
        if !weeklyNutritionDays.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("本周营养目标", systemImage: "calendar")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Text(WorkoutNutritionPlanner.planSourceLabel(preferences.nutritionPlanSource))
                        .font(.caption2.weight(.medium))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Theme.primary.opacity(0.22))
                        .clipShape(Capsule())
                }
                WeeklyNutritionStrip(
                    days: weeklyNutritionDays,
                    baselineCalories: healthContext?.baselineDailyBudget
                )
                if let caption = scheduleNutritionCaption {
                    Text(caption)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Theme.adaptiveAccent(colorScheme))
                }
                if !preferences.nutritionNotes.isEmpty {
                    Text(preferences.nutritionNotes)
                        .font(.caption)
                        .foregroundStyle(Theme.adaptiveTextPrimary(colorScheme))
                }
                Text("7 日目标随排课区分训练/休息；改日期后即时同步。今日摄入见首页。")
                    .font(.caption2)
                    .foregroundStyle(Theme.adaptiveTextSecondary(colorScheme))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .morandiCard()
        }
    }

    private var userSettings: UserSettings {
        settingsList.first ?? UserSettings()
    }

    private var selectedPlanStyle: WorkoutPlanStyle {
        preferencesList.first?.planStyle ?? .professional
    }

    private var shouldShowWeather: Bool {
        selectedPlanStyle.usesWeather || selectedPlanType.usesWeatherScheduling
    }

    private var isPlanConfigExpanded: Bool {
        planConfigExpanded ?? weekEntries.isEmpty
    }

    private var planConfigExpandedBinding: Binding<Bool> {
        Binding(
            get: { isPlanConfigExpanded },
            set: { planConfigExpanded = $0 }
        )
    }

    private var planConfigSummary: String {
        if weekEntries.isEmpty {
            return "选好类型与频率后，点「智能生成」或「AI 定制」"
        }
        if selectedPlanStyle == .professional {
            return "\(selectedPlanStyle.label) · \(selectedPlanType.label) · \(effectiveSessionsPerWeek)次/周 · 已生成本周计划"
        }
        return "\(selectedPlanStyle.label) · \(effectiveSessionsPerWeek)次/周 · 已生成本周计划"
    }

    private var planConfigSection: some View {
        CollapsibleSectionCard(
            title: "计划配置",
            systemImage: "slider.horizontal.3",
            subtitle: planConfigSummary,
            isExpanded: planConfigExpandedBinding
        ) {
            VStack(alignment: .leading, spacing: 12) {
                planConfigContent
                if shouldShowWeather {
                    weatherCardContent
                }
                if selectedPlanStyle == .moodWeather {
                    moodSchedulePreviewContent
                }
                actionButtons
            }
        }
    }

    /// 计划类型 + 每周频率
    private var planConfigContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("模式", selection: planStyleBinding) {
                ForEach(WorkoutPlanStyle.allCases) { style in
                    Label(style.label, systemImage: style.systemImage).tag(style)
                }
            }
            .pickerStyle(.segmented)

            Text(selectedPlanStyle.subtitle)
                .font(.caption2)
                .foregroundStyle(Theme.adaptiveTextSecondary(colorScheme))
                .frame(maxWidth: .infinity, alignment: .leading)

            if userSettings.prefersMoodWorkoutProfile, selectedPlanStyle == .professional {
                Label("小姜，试试「心情」模式：下雨游泳、晴天跳舞", systemImage: "heart.fill")
                    .font(.caption2)
                    .foregroundStyle(Theme.adaptiveAccent(colorScheme))
            }

            if selectedPlanStyle == .professional {
                HStack(alignment: .top, spacing: 0) {
                    VStack(alignment: .leading, spacing: 6) {
                        configFieldLabel("类型")
                        Picker("", selection: planTypeBinding) {
                            Section("健身房 · 力量") {
                                ForEach(WorkoutPlanType.gymStrengthTypes) { type in
                                    Label(type.label, systemImage: type.systemImage).tag(type)
                                }
                            }
                            Section("健身房 · 场地") {
                                ForEach(WorkoutPlanType.gymFacilityTypes) { type in
                                    Label(type.label, systemImage: type.systemImage).tag(type)
                                }
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .tint(Theme.adaptiveAccent(colorScheme))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Divider()
                        .padding(.vertical, 2)

                    VStack(alignment: .leading, spacing: 6) {
                        configFieldLabel("频率")
                        compactFrequencyControl
                    }
                    .frame(width: 148, alignment: .leading)
                }

                Text(selectedPlanType.subtitle)
                    .font(.caption2)
                    .foregroundStyle(Theme.adaptiveTextSecondary(colorScheme))
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                HStack {
                    configFieldLabel("频率")
                    Spacer()
                    compactFrequencyControl
                }
                Text("AI 会按 \(effectiveSessionsPerWeek) 场/周均衡分配舞蹈与游泳；点右侧标签可切换。")
                    .font(.caption2)
                    .foregroundStyle(Theme.adaptiveTextSecondary(colorScheme))
            }

            if preferences.inferredFromHealthKit, !preferences.healthKitWorkoutSummaryText.isEmpty, selectedPlanStyle == .professional {
                Label("已根据 Apple 健康近90天习惯推荐", systemImage: "heart.text.square.fill")
                    .font(.caption2)
                    .foregroundStyle(.green)
                Text(preferences.healthKitWorkoutSummaryText)
                    .font(.caption2)
                    .foregroundStyle(Theme.adaptiveTextSecondary(colorScheme))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var weatherCardContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(selectedPlanStyle == .moodWeather ? "心情 · 本周天气" : "本周晚间天气", systemImage: "cloud.sun.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.adaptiveTextPrimary(colorScheme))
                Spacer()
                if isLoadingWeather {
                    ProgressView().controlSize(.small)
                } else {
                    Button("刷新") {
                        Task { await refreshWeatherForecast() }
                    }
                    .font(.caption)
                }
            }

            if weatherSnapshot.isValid {
                Text(weatherSnapshot.cityLabel)
                    .font(.caption)
                    .foregroundStyle(Theme.adaptiveTextSecondary(colorScheme))

                ForEach(weatherDaysForDisplay) { day in
                    HStack {
                        Text(day.weekdayLabel)
                            .font(.caption.weight(.medium))
                            .frame(width: 36, alignment: .leading)
                        Text(day.eveningSummary)
                            .font(.caption2)
                            .foregroundStyle(Theme.adaptiveTextSecondary(colorScheme))
                        Spacer()
                        if selectedPlanStyle == .moodWeather {
                            moodActivityToggle(for: day)
                        } else {
                            Text(day.isGoodForEveningActivity ? "适宜" : "一般")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(day.isGoodForEveningActivity ? Theme.energyActive(colorScheme) : Theme.adaptiveTextTertiary(colorScheme))
                        }
                    }
                }

                if selectedPlanStyle == .moodWeather {
                    Text("下雨 → 游泳（\(MoodWorkoutTips.swimmingPackingList)）")
                        .font(.caption2)
                        .foregroundStyle(Theme.adaptiveTextTertiary(colorScheme))
                    Text("点「游泳/舞蹈」可切换；含周六日，下方预览为 AI 将采用的排课。")
                        .font(.caption2)
                        .foregroundStyle(Theme.adaptiveTextTertiary(colorScheme))
                } else {
                    Text("AI 定制将优先推荐 19:00 左右天气较好的工作日晚间。")
                        .font(.caption2)
                        .foregroundStyle(Theme.adaptiveTextTertiary(colorScheme))
                }
            } else if let err = locationService.lastError {
                Text(err)
                    .font(.caption)
                    .foregroundStyle(Theme.adaptiveWarning(colorScheme))
                Text("可在系统设置中允许位置权限，或仍可直接生成（AI 将默认工作日晚间）。")
                    .font(.caption2)
                    .foregroundStyle(Theme.adaptiveTextTertiary(colorScheme))
            } else {
                Text("正在获取本地天气…")
                    .font(.caption)
                    .foregroundStyle(Theme.adaptiveTextSecondary(colorScheme))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var moodScheduledSessions: [MoodWorkoutScheduler.ScheduledSession] {
        MoodWorkoutScheduler.schedule(
            sessionsCount: effectiveSessionsPerWeek,
            weather: weatherSnapshot.isValid ? weatherSnapshot : nil,
            overrides: moodDayOverrides,
            pinnedWeekdays: moodPinnedWeekdays ?? preferences.moodPinnedWeekdays
        )
    }

    @ViewBuilder
    private var moodSchedulePreviewContent: some View {
        let sessions = moodScheduledSessions
        let swimCount = sessions.filter { $0.activity == .swimming }.count
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("本周排课预览", systemImage: "calendar.badge.clock")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.adaptiveTextPrimary(colorScheme))
                Spacer()
                Text("游泳 \(swimCount) · 舞蹈 \(sessions.count - swimCount)")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(Theme.adaptiveTextSecondary(colorScheme))
            }

            ForEach(Array(sessions.enumerated()), id: \.element.id) { index, session in
                HStack(spacing: 8) {
                    Text(session.weekdayLabel)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.adaptiveAccent(colorScheme))
                        .frame(width: 36, alignment: .leading)
                    Image(systemName: session.activity == .swimming ? "figure.pool.swim" : "figure.dance")
                        .font(.caption)
                        .foregroundStyle(Theme.adaptiveTextSecondary(colorScheme))
                    Text(session.activity.label)
                        .font(.subheadline.weight(.medium))
                    if session.isUserOverride {
                        Text("已调整")
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Theme.adaptiveAccent(colorScheme).opacity(0.15))
                            .clipShape(Capsule())
                    }
                    Spacer()
                    Text("19:00")
                        .font(.caption2)
                        .foregroundStyle(Theme.adaptiveTextTertiary(colorScheme))
                }
                .contextMenu {
                    ForEach(alternateWeekdays(forSessionAt: index, in: sessions), id: \.self) { day in
                        Button("改到 \(MoodWorkoutScheduler.weekdayLabel(for: day))") {
                            repinMoodSession(at: index, to: day, sessions: sessions)
                        }
                    }
                    if moodPinnedWeekdays != nil || preferences.moodPinnedWeekdays != nil {
                        Button("恢复自动选日") {
                            clearMoodPinnedWeekdays()
                        }
                    }
                }
            }

            Text("长按预览行可更换训练日；生成计划后自动同步本周营养目标与消耗目标。")
                .font(.caption2)
                .foregroundStyle(Theme.adaptiveTextTertiary(colorScheme))

            if previewOutOfSyncWithSchedule {
                Text("预览日期与下方「本周安排」不一致，重新生成计划可同步。")
                    .font(.caption2)
                    .foregroundStyle(Theme.adaptiveWarning(colorScheme))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 已生成计划后，预览排课与持久化「本周安排」 weekday 不一致
    private var previewOutOfSyncWithSchedule: Bool {
        guard !weekEntries.isEmpty, selectedPlanStyle == .moodWeather else { return false }
        let saved = Set(weekEntries.map(\.dayOfWeek))
        let preview = Set(moodScheduledSessions.map(\.dayOfWeek))
        return saved != preview
    }

    private func moodActivity(for day: WeatherDayForecast) -> WorkoutPlanType {
        moodDayOverrides[day.weekday] ?? day.moodRecommendedActivity
    }

    private func moodActivityToggle(for day: WeatherDayForecast) -> some View {
        let activity = moodActivity(for: day)
        let isOverride = moodDayOverrides[day.weekday] != nil
        return Button {
            toggleMoodActivity(weekday: day.weekday, weatherDefault: day.moodRecommendedActivity)
        } label: {
            HStack(spacing: 4) {
                Text(activity.label)
                    .font(.caption2.weight(.semibold))
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.caption2)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                (activity == .swimming ? Theme.adaptiveAccent(colorScheme) : Theme.energyActive(colorScheme))
                    .opacity(isOverride ? 0.35 : 0.22)
            )
            .foregroundStyle(activity == .swimming ? Theme.adaptiveAccent(colorScheme) : Theme.energyActive(colorScheme))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("切换\(day.weekdayLabel)为\(activity == .swimming ? "舞蹈" : "游泳")")
    }

    private func toggleMoodActivity(weekday: Int, weatherDefault: WorkoutPlanType) {
        let current = moodDayOverrides[weekday] ?? weatherDefault
        let next: WorkoutPlanType = current == .swimming ? .dance : .swimming
        if next == weatherDefault {
            moodDayOverrides.removeValue(forKey: weekday)
        } else {
            moodDayOverrides[weekday] = next
        }
        persistMoodOverrides()
    }

    private func persistMoodOverrides() {
        let prefs = WorkoutPlanService.loadOrCreatePreferences(modelContext: modelContext)
        prefs.moodDayOverrides = moodDayOverrides
        try? modelContext.save()
    }

    private func loadMoodOverridesFromPreferences() {
        moodDayOverrides = preferences.moodDayOverrides
        moodPinnedWeekdays = preferences.moodPinnedWeekdays
    }

    private var weatherDaysForDisplay: [WeatherDayForecast] {
        guard weatherSnapshot.isValid else { return [] }
        if selectedPlanStyle == .moodWeather {
            return MoodWorkoutScheduler.displayDays(from: weatherSnapshot)
        }
        return Array(weatherSnapshot.days.prefix(5))
    }

    private func alternateWeekdays(forSessionAt index: Int, in sessions: [MoodWorkoutScheduler.ScheduledSession]) -> [Int] {
        let pool = MoodWorkoutScheduler.availableWeekdayPool(
            weather: weatherSnapshot.isValid ? weatherSnapshot : nil
        )
        let usedByOthers = Set(sessions.enumerated().compactMap { pair in
            pair.offset == index ? nil : pair.element.dayOfWeek
        })
        let current = sessions[index].dayOfWeek
        return pool.filter { $0 != current && !usedByOthers.contains($0) }
    }

    private func repinMoodSession(
        at index: Int,
        to newDay: Int,
        sessions: [MoodWorkoutScheduler.ScheduledSession]
    ) {
        var days = sessions.map(\.dayOfWeek)
        guard index < days.count else { return }
        days[index] = newDay
        moodPinnedWeekdays = days.sorted()
        persistMoodPinnedWeekdays()
        refreshNutritionCache()
    }

    private func clearMoodPinnedWeekdays() {
        moodPinnedWeekdays = nil
        persistMoodPinnedWeekdays()
        refreshNutritionCache()
    }

    private func persistMoodPinnedWeekdays() {
        let prefs = WorkoutPlanService.loadOrCreatePreferences(modelContext: modelContext)
        prefs.moodPinnedWeekdays = moodPinnedWeekdays
        try? modelContext.save()
    }

    private func configFieldLabel(_ title: String) -> some View {
        Text(title)
            .font(.caption)
            .foregroundStyle(Theme.adaptiveTextSecondary(colorScheme))
    }

    private var compactFrequencyControl: some View {
        HStack(spacing: 10) {
            Text("\(effectiveSessionsPerWeek) 次/周")
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .frame(minWidth: 52, alignment: .leading)

            Button {
                adjustSessionsPerWeek(by: -1)
            } label: {
                Image(systemName: "minus")
                    .font(.caption.weight(.bold))
                    .frame(width: 28, height: 28)
                    .background(Theme.adaptiveTextSecondary(colorScheme).opacity(0.12))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(effectiveSessionsPerWeek <= 2)

            Button {
                adjustSessionsPerWeek(by: 1)
            } label: {
                Image(systemName: "plus")
                    .font(.caption.weight(.bold))
                    .frame(width: 28, height: 28)
                    .background(Theme.adaptiveAccent(colorScheme).opacity(0.18))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(effectiveSessionsPerWeek >= 6)
        }
    }

    private func adjustSessionsPerWeek(by delta: Int) {
        let prefs = WorkoutPlanService.loadOrCreatePreferences(modelContext: modelContext)
        prefs.sessionsPerWeek = min(max(prefs.sessionsPerWeek + delta, 2), 6)
        prefs.updatedAt = Date()
        try? modelContext.save()
        refreshNutritionCache()
    }

    private func persistMoodOverridesBeforeGenerate() {
        persistMoodOverrides()
    }

    @ViewBuilder
    private var planOutputCard: some View {
        let hasSummary = !preferences.weeklySummaryText.isEmpty
        let hasDiet = !preferences.dietAdviceText.isEmpty
        if hasSummary || hasDiet {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center) {
                    Text("本周概要")
                        .font(.subheadline.weight(.semibold))
                    Spacer(minLength: 8)
                    if !preferences.lastGeneratedSource.isEmpty {
                        Text(preferences.lastGeneratedSource == "ai" ? "AI" : "规则")
                            .font(.caption2.weight(.medium))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Theme.primary.opacity(0.25))
                            .clipShape(Capsule())
                    }
                }

                if hasSummary {
                    Text(preferences.weeklySummaryText)
                        .font(.caption)
                        .foregroundStyle(Theme.adaptiveTextSecondary(colorScheme))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if hasSummary && hasDiet {
                    Divider()
                }

                if hasDiet {
                    Label("饮食摄入建议", systemImage: "leaf.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.macroProtein(colorScheme))
                    Text(preferences.dietAdviceText)
                        .font(.caption)
                        .foregroundStyle(Theme.adaptiveTextPrimary(colorScheme))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .morandiCard()
        }
    }

    private var planTypeBinding: Binding<WorkoutPlanType> {
        Binding(
            get: { selectedPlanType },
            set: { applyPlanType($0) }
        )
    }

    private var planStyleBinding: Binding<WorkoutPlanStyle> {
        Binding(
            get: { selectedPlanStyle },
            set: { applyPlanStyle($0) }
        )
    }

    private func applyPlanStyle(_ style: WorkoutPlanStyle) {
        let prefs = WorkoutPlanService.loadOrCreatePreferences(modelContext: modelContext)
        prefs.planStyle = style
        if style == .moodWeather, prefs.sessionsPerWeek > 3 {
            prefs.sessionsPerWeek = 2
        }
        try? modelContext.save()
        if style.usesWeather {
            Task { await refreshWeatherForecast() }
        }
    }

    private var selectedPlanType: WorkoutPlanType {
        preferencesList.first?.planType ?? .balanced
    }

    private func applyPlanType(_ type: WorkoutPlanType) {
        let prefs = WorkoutPlanService.loadOrCreatePreferences(modelContext: modelContext)
        prefs.planType = type
        if prefs.sessionsPerWeek != type.recommendedSessionsPerWeek {
            prefs.sessionsPerWeek = type.recommendedSessionsPerWeek
        }
        try? modelContext.save()
        if type.usesWeatherScheduling {
            Task { await refreshWeatherForecast() }
        }
    }

    private func refreshWeatherForecast() async {
        guard shouldShowWeather else { return }
        isLoadingWeather = true
        defer { isLoadingWeather = false }
        weatherSnapshot = await WeatherService.fetchWeeklyEveningForecast(locationService: locationService)
        refreshNutritionCache()
    }

    private var actionButtons: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("确认类型与频率后，生成本周计划")
                .font(.caption2)
                .foregroundStyle(Theme.adaptiveTextSecondary(colorScheme))

            Button {
                Task { await generateRuleBased() }
            } label: {
                Label(isGenerating ? "生成中…" : "智能生成（规则）", systemImage: "wand.and.stars")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(MorandiQuickActionButtonStyle(variant: .primary))
            .disabled(isGenerating)

            Button {
                Task { await generateWithAI() }
            } label: {
                Label("AI 定制计划", systemImage: "sparkles")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(MorandiQuickActionButtonStyle(variant: .secondary))
            .disabled(isGenerating)

            if !APIKeyManager.isDeepSeekConfigured {
                Text("AI 定制需先在「我的 → AI 配置」设置 DeepSeek Key")
                    .font(.caption2)
                    .foregroundStyle(Theme.adaptiveTextSecondary(colorScheme))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var progressCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("本周完成度")
                    .font(.subheadline.weight(.semibold))
                Spacer(minLength: 8)
                Text("\(progress.completedSessions)/\(max(progress.totalSessions, 1)) 场 · 按组数")
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
            }
            ProgressView(value: progressFraction)
                .tint(Theme.adaptiveAccent(colorScheme))

            if weeklyBurnGoal > 0 {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline) {
                        Label(
                            weeklyBurnUsesHealthData ? "运动消耗（锻炼记录）" : "运动消耗（组数估算）",
                            systemImage: "figure.run"
                        )
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.macroProtein(colorScheme))
                        Spacer(minLength: 8)
                        Text("\(Int(weeklyBurnCompleted)) / \(Int(weeklyBurnGoal)) kcal")
                            .font(.caption.weight(.semibold))
                            .monospacedDigit()
                    }
                    ProgressView(value: burnProgressFraction)
                        .tint(Theme.macroProtein(colorScheme))
                    if weeklyBurnCompletedInfo.usesHealthData {
                        Text("已完成 = 本周 Apple 健康锻炼消耗；目标 = 训练计划应消耗")
                            .font(.caption2)
                            .foregroundStyle(Theme.adaptiveTextSecondary(colorScheme))
                    } else if weeklyBurnCompleted > 0 {
                        Text("无锻炼记录时，按已勾选组数估算完成消耗")
                            .font(.caption2)
                            .foregroundStyle(Theme.adaptiveTextSecondary(colorScheme))
                    } else {
                        Text("连接 Apple Watch 并完成锻炼后，将对比计划运动消耗")
                            .font(.caption2)
                            .foregroundStyle(Theme.adaptiveTextSecondary(colorScheme))
                    }
                    if let deficit = healthContext?.dailyDeficit, deficit > 0, weeklyBurnCompletedInfo.usesHealthData {
                        Text("每日缺口约 \(Int(deficit)) kcal，训练承担约 \(Int(deficit * 0.35)) kcal")
                            .font(.caption2)
                            .foregroundStyle(Theme.adaptiveTextSecondary(colorScheme))
                    }
                }
            }

            HStack {
                Label("\(progress.completedMinutes) 分钟", systemImage: "clock")
                Spacer()
                if progress.watchMatchedSessions > 0 {
                    Label("Watch 匹配 \(progress.watchMatchedSessions)", systemImage: "applewatch")
                }
            }
            .font(.caption)
            .foregroundStyle(Theme.adaptiveTextSecondary(colorScheme))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .morandiCard()
    }

    @ViewBuilder
    private var planCoachSection: some View {
        if !weekEntries.isEmpty {
            WorkoutPlanCoachSection(
                weekStart: weekStart,
                weekEntries: weekEntries,
                exercisesBySession: exercisesBySession,
                todayEntry: todayEntry,
                phaseLabel: phaseInfo.label,
                healthProfile: healthProfileSummary,
                genderLabel: genderLabel,
                onPlanUpdated: {
                    Task { await loadWeek(force: true) }
                }
            )
        }
    }

    @ViewBuilder
    private var scheduleSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("本周安排")

            if weekEntries.isEmpty {
                Text("还没有训练计划。选好类型与频率后，点上方「智能生成」或「AI 定制」。")
                    .font(.caption)
                    .foregroundStyle(Theme.adaptiveTextSecondary(colorScheme))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .morandiCard()
            } else {
                ForEach(weekEntries, id: \.id) { entry in
                    workoutRow(entry)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var watchHistorySection: some View {
        let workouts = healthContext?.healthKitService.recentWorkouts ?? []
        if !workouts.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                sectionHeader("近 7 天 Apple 健康锻炼")
                VStack(spacing: 0) {
                    ForEach(Array(workouts.prefix(5).enumerated()), id: \.element.id) { index, item in
                        HStack {
                            Text(item.activityLabel)
                                .font(.subheadline)
                            Spacer(minLength: 8)
                            Text("\(Int(item.durationMinutes)) 分钟")
                                .font(.caption)
                                .foregroundStyle(Theme.adaptiveTextSecondary(colorScheme))
                                .monospacedDigit()
                        }
                        .padding(.vertical, 10)
                        if index < min(workouts.count, 5) - 1 {
                            Divider()
                        }
                    }
                }
                .morandiCard()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.subheadline.weight(.semibold))
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var disclaimer: some View {
        Text("训练与饮食建议仅供参考，请遵医嘱。如有不适请停止运动并咨询医生。")
            .font(.caption2)
            .foregroundStyle(Theme.adaptiveTextSecondary(colorScheme))
            .multilineTextAlignment(.center)
            .padding(.top, 8)
    }

    // MARK: - Row

    private func workoutRow(_ entry: WorkoutPlanEntry) -> some View {
        NavigationLink {
            WorkoutSessionDetailView(entry: entry)
        } label: {
            workoutRowContent(entry)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Menu("更改日期") {
                ForEach(WorkoutPlanEntry.weekdayOptions, id: \.day) { option in
                    Button {
                        WorkoutPlanService.rescheduleEntry(
                            entry,
                            toDayOfWeek: option.day,
                            weekEntries: weekEntries,
                            weekStart: weekStart,
                            modelContext: modelContext
                        )
                        reloadEntries()
                        Task { await refreshHealthContext() }
                    } label: {
                        if entry.dayOfWeek == option.day {
                            Label(option.label, systemImage: "checkmark")
                        } else {
                            Text(option.label)
                        }
                    }
                }
            }
            Divider()
            ForEach(WorkoutSessionFocus.allCases) { focus in
                Button("改为 \(focus.label)") {
                    WorkoutPlanService.applySessionFocus(entry, focus: focus, modelContext: modelContext)
                    reloadEntries()
                }
            }
        }
    }

    private func workoutRowContent(_ entry: WorkoutPlanEntry) -> some View {
        let exercises = exercisesBySession[entry.id] ?? []
        let exerciseCount = exercises.count
        let muscleGroups = Array(Set(exercises.map(\.muscleGroup).filter { !$0.isEmpty }))
        let isFacilitySession = isMoodFacilitySession(entry)
        let detailLine = facilitySessionDetailLine(entry: entry, exercises: exercises)
        return HStack(alignment: .top, spacing: 12) {
            Button {
                WorkoutPlanService.toggleCompleted(entry, modelContext: modelContext)
                reloadEntries()
            } label: {
                Image(systemName: entry.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(entry.isCompleted ? Theme.adaptiveAccent(colorScheme) : Theme.adaptiveTextSecondary(colorScheme))
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(entry.weekdayLabel)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.adaptiveAccent(colorScheme))
                    Text(entry.workoutType)
                        .font(.headline)
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(Theme.adaptiveTextSecondary(colorScheme))
                }
                Text("\(entry.targetMinutes) 分钟 · 目标 \(Int(entry.targetCalories)) kcal")
                    .font(.caption)
                    .foregroundStyle(Theme.adaptiveTextSecondary(colorScheme))
                if isFacilitySession, let detailLine {
                    Text(detailLine)
                        .font(.caption2)
                        .foregroundStyle(Theme.adaptiveTextSecondary(colorScheme))
                } else if exerciseCount > 0 {
                    HStack(spacing: 6) {
                        Text("\(exerciseCount) 个动作 · 点进查看组数/次数")
                            .font(.caption2)
                            .foregroundStyle(Theme.adaptiveTextSecondary(colorScheme))
                        ForEach(muscleGroups.prefix(5), id: \.self) { group in
                            Circle()
                                .fill(MuscleGroupPalette.color(for: group, scheme: colorScheme))
                                .frame(width: 7, height: 7)
                        }
                    }
                }
                if !entry.notes.isEmpty {
                    Text(entry.notes)
                        .font(.caption2)
                        .foregroundStyle(Theme.adaptiveTextSecondary(colorScheme))
                        .lineLimit(isFacilitySession ? 3 : 2)
                }
            }
            Spacer()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.cardBackground(colorScheme))
        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadiusCard))
        .opacity(entry.isCompleted ? 0.75 : 1)
    }

    private func isMoodFacilitySession(_ entry: WorkoutPlanEntry) -> Bool {
        if preferences.planStyle == .moodWeather { return true }
        return entry.workoutType == WorkoutPlanType.dance.label
            || entry.workoutType == WorkoutPlanType.swimming.label
    }

    private func facilitySessionDetailLine(entry: WorkoutPlanEntry, exercises: [WorkoutExercise]) -> String? {
        guard let first = exercises.first else { return nil }
        let reps = first.reps.trimmingCharacters(in: .whitespacesAndNewlines)
        if reps.isEmpty {
            return "约 \(entry.targetMinutes) 分钟 · \(Int(entry.targetCalories)) kcal"
        }
        return "\(reps) · \(Int(first.targetCalories > 0 ? first.targetCalories : entry.targetCalories)) kcal"
    }

    // MARK: - Bindings & logic

    private var effectiveSessionsPerWeek: Int {
        let stored = preferencesList.first?.sessionsPerWeek ?? 4
        return min(max(stored, 2), 6)
    }

    private var progressFraction: Double {
        guard progress.totalSessions > 0 else { return 0 }
        return Double(progress.completedSessions) / Double(progress.totalSessions)
    }

    private func reloadEntries() {
        weekEntries = WorkoutPlanService.entriesForWeek(weekStart, modelContext: modelContext)
        var cache: [UUID: [WorkoutExercise]] = [:]
        for entry in weekEntries {
            cache[entry.id] = WorkoutPlanService.exercises(for: entry.id, modelContext: modelContext)
        }
        exercisesBySession = cache
        refreshNutritionCache()
    }

    /// 按「本周安排」或排课预览刷新 7 日营养条（训练日/休息日目标分别切换）
    private func refreshNutritionCache() {
        guard WorkoutNutritionPlanner.hasActivePlan(preferencesList.first),
              let prefs = preferencesList.first else {
            weeklyNutritionDaysCache = []
            return
        }
        weeklyNutritionDaysCache = WorkoutNutritionPlanner.weeklyNutritionDays(
            prefs: prefs,
            trainingWeekdays: trainingWeekdaysForNutrition,
            weekStart: weekStart,
            baselineCalories: healthContext?.baselineDailyBudget
        )
    }

    private func loadWeek(force: Bool = false) async {
        guard !isLoadingWeek || force else { return }
        isLoadingWeek = true
        defer { isLoadingWeek = false }

        reloadEntries()
        let isTrainingDay = WorkoutPlanService.hasPlannedSession(modelContext: modelContext)
        await healthContext?.refreshNutritionAndEnergy(
            foodEntries: foodEntries,
            goals: goals,
            weightEntries: weightEntries,
            cycleProfiles: cycleProfiles,
            workoutPreferences: preferencesList.first,
            isTrainingDayToday: isTrainingDay
        )
        reloadEntries()

        await healthContext?.healthKitService.fetchRecentWorkouts(days: 14)
        if let healthKit = healthContext?.healthKitService {
            _ = await WorkoutPlanService.inferPreferencesFromHealthKitIfNeeded(
                healthKit: healthKit,
                modelContext: modelContext
            )
        }
        WorkoutPlanService.syncCompletionFromHealthKit(
            entries: weekEntries,
            workouts: healthContext?.healthKitService.recentWorkouts ?? [],
            weekStart: weekStart,
            modelContext: modelContext
        )
        reloadEntries()
        if shouldShowWeather {
            await refreshWeatherForecast()
        }
        WorkoutMorningReminderService.sync(modelContext: modelContext)
    }

    private func refreshHealthContext() async {
        let isTrainingDay = WorkoutPlanService.hasPlannedSession(modelContext: modelContext)
        await healthContext?.refreshNutritionAndEnergy(
            foodEntries: foodEntries,
            goals: goals,
            weightEntries: weightEntries,
            cycleProfiles: cycleProfiles,
            workoutPreferences: preferencesList.first,
            isTrainingDayToday: isTrainingDay
        )
        reloadEntries()
    }

    private func generateRuleBased() async {
        isGenerating = true
        defer { isGenerating = false }
        await refreshHealthContext()

        let prefs = WorkoutPlanService.loadOrCreatePreferences(modelContext: modelContext)
        persistMoodOverridesBeforeGenerate()
        if prefs.planStyle.usesWeather || prefs.planType.usesWeatherScheduling {
            await refreshWeatherForecast()
        }
        let input = WorkoutPlanService.buildEngineInput(
            preferences: prefs,
            healthContext: healthContext,
            userGoal: goals.first,
            currentWeight: currentWeight,
            recentWorkouts: healthContext?.healthKitService.recentWorkouts ?? [],
            profileNickname: settingsList.first?.profileNickname ?? ""
        )
        let output = WorkoutPlanEngine.calculate(input, weather: weatherSnapshot)

        do {
            try WorkoutPlanService.savePlan(
                output,
                phase: phaseInfo.phase,
                source: "engine",
                weekStart: weekStart,
                modelContext: modelContext
            )
            reloadEntries()
            await refreshHealthContext()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func generateWithAI() async {
        guard APIKeyManager.isDeepSeekConfigured else {
            showAPIKeySetup = true
            return
        }

        isGenerating = true
        defer { isGenerating = false }
        await refreshHealthContext()

        let prefs = WorkoutPlanService.loadOrCreatePreferences(modelContext: modelContext)
        persistMoodOverridesBeforeGenerate()
        if prefs.planStyle.usesWeather || prefs.planType.usesWeatherScheduling {
            await refreshWeatherForecast()
        }

        let context = WorkoutPlanService.buildAIContext(
            preferences: prefs,
            healthContext: healthContext,
            userGoal: goals.first,
            currentWeight: currentWeight,
            recentWorkouts: healthContext?.healthKitService.recentWorkouts ?? [],
            weatherSnapshot: weatherSnapshot,
            profileNickname: settingsList.first?.profileNickname ?? ""
        )

        do {
            let output = try await WorkoutPlanAIService.generatePlan(
                context: context,
                weeklySessions: prefs.sessionsPerWeek,
                planType: prefs.planType,
                planStyle: prefs.planStyle,
                excluded: prefs.excludedExercises,
                fallbackBudget: healthContext?.dailyCalorieBudget,
                fallbackProtein: healthContext?.macroTargets?.proteinGrams
            )
            try WorkoutPlanService.savePlan(
                output,
                phase: phaseInfo.phase,
                source: "ai",
                weekStart: weekStart,
                modelContext: modelContext
            )
            reloadEntries()
            await refreshHealthContext()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#Preview {
    NavigationStack {
        WorkoutPlanView()
    }
    .modelContainer(for: [
        WorkoutPlanEntry.self,
        WorkoutPlanPreferences.self,
        UserGoal.self,
        FoodEntry.self
    ], inMemory: true)
    .healthContext(UnifiedHealthContext())
}
