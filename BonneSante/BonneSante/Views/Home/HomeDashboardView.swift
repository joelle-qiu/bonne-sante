import SwiftUI
import SwiftData

/// 首页仪表盘（Bonne-Santé）
/// 信息层级：每日刷新数据（能量/营养）优先；复查待办置后。
/// @author jiali.qiu
struct HomeDashboardView: View {
    @Environment(\.healthContext) private var context

    @Query(sort: \FoodEntry.createdAt, order: .reverse) private var allEntries: [FoodEntry]
    @Query private var goals: [UserGoal]
    @Query(sort: \WeightEntry.date, order: .reverse) private var weightEntries: [WeightEntry]
    @Query private var cycleProfiles: [CycleProfile]
    @Query(sort: \Report.importDate, order: .reverse) private var reports: [Report]
    @Query(filter: #Predicate<RiskFlag> { !$0.isResolved }) private var riskFlags: [RiskFlag]
    @Query(sort: \TodoItem.dueDate) private var todos: [TodoItem]
    @Query private var checkupPlans: [CheckupPlan]
    @Query private var workoutPreferences: [WorkoutPlanPreferences]

    @Environment(\.modelContext) private var modelContext

    @State private var showImport = false
    @State private var todayWorkout: WorkoutPlanEntry?
    @State private var todayExerciseCount = 0
    @State private var todayMuscleGroups: [String] = []
    @State private var nextWorkout: WorkoutPlanEntry?
    @State private var nextWorkoutExerciseCount = 0
    @State private var showShareSheet = false
    @State private var shareImage: UIImage?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if let ctx = context {
                        phaseSection(ctx)
                        insightCarouselSection(ctx)
                        dailyEnergySection(ctx)
                        nutritionSection()
                        quickActions
                        cycleTipsSection(ctx)
                        foodListSection
                        todayScheduleSection()
                        checkupRemindersSection(ctx)
                    } else {
                        ProgressView("加载中…")
                    }
                }
                .padding(.horizontal, Theme.horizontalPadding)
                .padding(.vertical, 16)
            }
            .cycleThemedPageBackground()
            .navigationTitle("仪表盘")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        prepareShareImage()
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .accessibilityLabel("分享今日健康摘要")
                }
            }
            .sheet(isPresented: $showShareSheet) {
                if let shareImage {
                    ActivityView(activityItems: [shareImage])
                }
            }
            .task { await refreshContext() }
            .refreshable { await refreshContext() }
            .sheet(isPresented: $showImport) {
                ReportImportView()
            }
        }
    }

    @Environment(\.colorScheme) private var colorScheme

    private func phaseSection(_ ctx: UnifiedHealthContext) -> some View {
        PhaseBar(
            label: ctx.cyclePhaseInfo.label,
            phase: ctx.cyclePhaseInfo.phase,
            daysUntilNextPeriod: ctx.cyclePhaseInfo.daysUntilNextPeriod,
            dataSourceLabel: ctx.cyclePhaseInfo.phase == .unknown ? nil : ctx.cyclePhaseInfo.dataSource.label
        )
        .morandiCardAppear()
    }

    @ViewBuilder
    private func insightCarouselSection(_ ctx: UnifiedHealthContext) -> some View {
        let items = buildInsightItems(ctx)
        if !items.isEmpty {
            HomeInsightCarousel(items: items)
        }
    }

    private func buildInsightItems(_ ctx: UnifiedHealthContext) -> [HomeInsightCarousel.Item] {
        var items: [HomeInsightCarousel.Item] = []

        if let entry = todayWorkout {
            items.append(HomeInsightCarousel.Item(
                id: "today-workout",
                symbol: "figure.run",
                tint: Theme.energyActive(colorScheme),
                title: "今日训练",
                subtitle: "\(entry.weekdayLabel) · \(entry.workoutType) · \(entry.targetMinutes) 分钟"
            ))
        } else if let entry = nextWorkout {
            items.append(HomeInsightCarousel.Item(
                id: "next-workout",
                symbol: "calendar.badge.clock",
                tint: Theme.adaptiveAccent(colorScheme),
                title: "下场训练",
                subtitle: "\(entry.weekdayLabel) · \(entry.workoutType)"
            ))
        }

        if let plan = ctx.upcomingCheckupPlans.first {
            let days = Calendar.current.dateComponents(
                [.day],
                from: Calendar.current.startOfDay(for: Date()),
                to: Calendar.current.startOfDay(for: plan.nextDueDate)
            ).day ?? 0
            let when = days <= 0 ? "建议尽快安排" : (days <= 30 ? "\(days) 天后" : ReportDisplayFormatter.examDateLabel(plan.nextDueDate))
            items.append(HomeInsightCarousel.Item(
                id: "checkup",
                symbol: "stethoscope",
                tint: Theme.brandPrimary(colorScheme),
                title: "复查提醒",
                subtitle: "\(plan.metricName) · \(when)"
            ))
        }

        let activeRisks = riskFlags.prefix(3)
        if !activeRisks.isEmpty {
            items.append(HomeInsightCarousel.Item(
                id: "risk",
                symbol: "exclamationmark.triangle.fill",
                tint: Theme.adaptiveWarning(colorScheme),
                title: "健康关注",
                subtitle: activeRisks.map(\.metricName).joined(separator: " · ")
            ))
        }

        let tip = ctx.cyclePhaseInfo.tip
        if !tip.isEmpty {
            items.append(HomeInsightCarousel.Item(
                id: "cycle-tip",
                symbol: "sparkles",
                tint: Theme.adaptiveAccent(colorScheme),
                title: ctx.cyclePhaseInfo.phase == .unknown ? "周期提示" : ctx.cyclePhaseInfo.label,
                subtitle: tip
            ))
        }

        return items
    }

    private func prepareShareImage() {
        guard let ctx = context else { return }
        let remaining = Int(ctx.remainingCalories ?? 0)
        let budget = Int(ctx.dailyCalorieBudget ?? 0)
        let consumed = Int(ctx.caloriesConsumed)
        let checkup = ctx.upcomingCheckupPlans.first.map { plan in
            "复查：\(plan.metricName) · \(ReportDisplayFormatter.examDateLabel(plan.nextDueDate))"
        }
        let workout: String? = {
            if let entry = todayWorkout {
                return "训练：\(entry.workoutType) · \(entry.targetMinutes) 分钟"
            }
            if let entry = nextWorkout {
                return "下场：\(entry.weekdayLabel) \(entry.workoutType)"
            }
            return nil
        }()

        let card = HealthSummaryShareCard(
            dateLabel: Date().formatted(date: .complete, time: .omitted),
            phaseLabel: ctx.cyclePhaseInfo.label,
            remainingCalories: remaining,
            consumedCalories: consumed,
            budgetCalories: budget,
            proteinGrams: Int(todayEntries.reduce(0) { $0 + $1.protein }),
            carbsGrams: Int(todayEntries.reduce(0) { $0 + $1.carbohydrates }),
            fatGrams: Int(todayEntries.reduce(0) { $0 + $1.fat }),
            checkupHint: checkup,
            workoutHint: workout
        )
        shareImage = HealthSummaryShareRenderer.renderImage(from: card)
        showShareSheet = shareImage != nil
    }

    @ViewBuilder
    private func dailyEnergySection(_ ctx: UnifiedHealthContext) -> some View {
        if let budget = ctx.dailyCalorieBudget, let remaining = ctx.remainingCalories {
            let intel = ctx.intelligenceProfile
            let resting = intel?.bmrKcal
                ?? (ctx.userGoal?.calculateBMR(currentWeight: ctx.currentWeight ?? 0) ?? 0)
            let activeBaseline = intel?.avgActiveKcal7d
                ?? (ctx.isUsingWatchData ? ctx.healthKitService.activeCaloriesBurned : max(ctx.caloriesBurned - resting, 0))
            let total = intel?.tdeeKcal ?? ctx.caloriesBurned

            DailyEnergyBoard(
                remaining: remaining,
                budget: budget,
                consumed: ctx.caloriesConsumed,
                activeEnergy: activeBaseline,
                basalEnergy: resting,
                totalBurned: total,
                isUsingWatchData: ctx.isUsingWatchData,
                bmrSourceLabel: intel?.bmrSourceShort,
                tdeeSourceLabel: intel?.tdeeSourceShort,
                todayActiveEnergy: ctx.healthKitService.activeCaloriesBurned,
                activeSourceLabel: intel?.avgActiveKcal7d != nil ? "7日均值" : nil
            )
        } else {
            EmptyStateView(
                symbol: "target",
                title: "先设定减脂目标",
                message: "在「训练」页设置当前体重与目标体重后，这里会显示每日能量看板。",
                actionTitle: nil,
                action: nil
            )
            .frame(height: 200)
        }
    }

    private func nutritionSection() -> some View {
        let protein = todayEntries.reduce(0) { $0 + $1.protein }
        let carbs = todayEntries.reduce(0) { $0 + $1.carbohydrates }
        let fat = todayEntries.reduce(0) { $0 + $1.fat }
        let calories = todayEntries.reduce(0) { $0 + $1.calories }
        let targets = context?.macroTargets

        return NutritionMacroBars(
            protein: protein,
            carbs: carbs,
            fat: fat,
            calories: calories,
            proteinTarget: targets?.proteinGrams,
            carbsTarget: targets?.carbGrams,
            fatTarget: targets?.fatGrams,
            subtitle: context?.nutritionAdjustmentNote
                ?? context?.nutritionPlanSource.map { WorkoutNutritionPlanner.planSourceLabel($0) }
        )
    }

    @ViewBuilder
    private func todayScheduleSection() -> some View {
        CompactTodaySchedule(
            todayWorkout: todayWorkout,
            todayExerciseCount: todayExerciseCount,
            todayMuscleGroups: todayMuscleGroups,
            nextWorkout: todayWorkout == nil ? nextWorkout : nil,
            nextWorkoutExerciseCount: nextWorkoutExerciseCount,
            appointments: upcomingAppointments
        )
    }

    private var upcomingAppointments: [TodoItem] {
        let startOfToday = Calendar.current.startOfDay(for: Date())
        return todos
            .filter { $0.sourceType == .appointment && !$0.isCompleted && $0.dueDate >= startOfToday }
            .sorted { $0.dueDate < $1.dueDate }
            .prefix(2)
            .map { $0 }
    }

    private func loadWorkoutSchedule() {
        let weekStart = WorkoutPlanService.startOfWeek()
        let entries = WorkoutPlanService.entriesForWeek(weekStart, modelContext: modelContext)
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        todayWorkout = entries.first { entry in
            guard let date = WorkoutPlanService.sessionDate(for: entry) else { return false }
            return calendar.isDate(date, inSameDayAs: today)
        }

        if let entry = todayWorkout {
            let exercises = WorkoutPlanService.exercises(for: entry.id, modelContext: modelContext)
            todayExerciseCount = exercises.count
            todayMuscleGroups = Array(Set(exercises.map(\.muscleGroup).filter { !$0.isEmpty }))
        } else {
            todayExerciseCount = 0
            todayMuscleGroups = []
        }

        let upcoming = entries
            .compactMap { entry -> (WorkoutPlanEntry, Date)? in
                guard let date = WorkoutPlanService.sessionDate(for: entry),
                      !entry.isCompleted,
                      date >= today else { return nil }
                return (entry, date)
            }
            .sorted { $0.1 < $1.1 }

        if let next = upcoming.first {
            nextWorkout = next.0
            nextWorkoutExerciseCount = WorkoutPlanService.exercises(for: next.0.id, modelContext: modelContext).count
        } else {
            nextWorkout = nil
            nextWorkoutExerciseCount = 0
        }
    }

    @ViewBuilder
    private func checkupRemindersSection(_ ctx: UnifiedHealthContext) -> some View {
        CompactCheckupReminders(plans: ctx.upcomingCheckupPlans)
    }

    @ViewBuilder
    private func cycleTipsSection(_ ctx: UnifiedHealthContext) -> some View {
        if ctx.cyclePhaseInfo.phase == .unknown {
            tipCard(ctx.cyclePhaseInfo.tip)
        } else {
            CycleTipsCard(phaseInfo: ctx.cyclePhaseInfo, compact: true)
        }
    }

    private func tipCard(_ tip: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "sparkles")
                .font(.caption)
                .foregroundStyle(Theme.adaptiveAccent(colorScheme))
            Text(tip)
                .font(.caption)
                .foregroundStyle(Theme.adaptiveTextSecondary(colorScheme))
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Theme.cardBackground(colorScheme))
        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadiusCard))
    }

    private var quickActions: some View {
        HStack(spacing: 12) {
            NavigationLink {
                FoodInputView()
            } label: {
                Label("记录饮食", systemImage: "fork.knife")
            }
            .buttonStyle(MorandiQuickActionButtonStyle(variant: .primary))

            Button { showImport = true } label: {
                Label("导入报告", systemImage: "doc.text.viewfinder")
            }
            .buttonStyle(MorandiQuickActionButtonStyle(variant: .secondary))
        }
    }

    private var todayEntries: [FoodEntry] {
        let start = Calendar.current.startOfDay(for: Date())
        return allEntries.filter { $0.createdAt >= start }
    }

    private var foodListSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("今日饮食")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.adaptiveTextPrimary(colorScheme))
                Spacer()
                if !todayEntries.isEmpty {
                    Text("\(todayEntries.count) 条")
                        .font(.caption)
                        .foregroundStyle(Theme.adaptiveTextSecondary(colorScheme))
                }
            }

            Group {
                if todayEntries.isEmpty {
                    Text("还没有记录，点击「记录饮食」开始。")
                        .font(.caption)
                        .foregroundStyle(Theme.adaptiveTextSecondary(colorScheme))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 4)
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(todayEntries.prefix(3).enumerated()), id: \.element.id) { index, entry in
                            FoodEntryRow(entry: entry)
                            if index < min(todayEntries.count, 3) - 1 {
                                Divider()
                            }
                        }
                        if todayEntries.count > 3 {
                            Text("还有 \(todayEntries.count - 3) 条记录")
                                .font(.caption2)
                                .foregroundStyle(Theme.adaptiveTextSecondary(colorScheme))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.top, 8)
                        }
                    }
                }
            }
            .morandiCard()
        }
    }

    private func refreshContext() async {
        loadWorkoutSchedule()
        await context?.refresh(
            foodEntries: allEntries,
            goals: goals,
            weightEntries: weightEntries,
            cycleProfiles: cycleProfiles,
            reports: reports,
            riskFlags: riskFlags,
            todos: todos,
            checkupPlans: checkupPlans,
            workoutPreferences: workoutPreferences.first,
            isTrainingDayToday: todayWorkout != nil
        )
        syncUserGoalFromHealthKit()
    }

    /// 将 Apple 健康中的年龄/身高等写回 UserGoal（避免界面仍显示默认 30 岁）
    private func syncUserGoalFromHealthKit() {
        guard let goal = goals.first,
              let profile = context?.healthKitService.bodyProfile else { return }
        goal.mergeHealthKitProfile(profile, modelContext: modelContext)
    }
}

#Preview {
    HomeDashboardView()
        .modelContainer(for: [FoodEntry.self, UserGoal.self, WeightEntry.self, CycleProfile.self], inMemory: true)
        .healthContext(UnifiedHealthContext())
}
