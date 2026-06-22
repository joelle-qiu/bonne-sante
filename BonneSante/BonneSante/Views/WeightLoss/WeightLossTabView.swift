import SwiftUI
import SwiftData

/// 营养 Tab：饮食记录、历史与 AI 顾问
/// @author jiali.qiu
struct WeightLossTabView: View {
    @Environment(\.healthContext) private var healthContext
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme

    @Query(sort: \FoodEntry.createdAt, order: .reverse) private var allEntries: [FoodEntry]
    @Query private var goals: [UserGoal]
    @Query(sort: \WeightEntry.date, order: .reverse) private var weightEntries: [WeightEntry]
    @Query private var cycleProfiles: [CycleProfile]
    @Query(sort: \Report.importDate, order: .reverse) private var reports: [Report]
    @Query(filter: #Predicate<RiskFlag> { !$0.isResolved }) private var riskFlags: [RiskFlag]
    @Query(sort: \TodoItem.dueDate) private var todos: [TodoItem]
    @Query private var checkupPlans: [CheckupPlan]
    @Query private var workoutPreferences: [WorkoutPlanPreferences]

    @State private var weekEntriesCache: [WorkoutPlanEntry] = []
    @State private var weeklyNutritionDaysCache: [WorkoutNutritionPlanner.WeeklyNutritionDay] = []

    private var currentGoal: UserGoal? { goals.first }

    private var weekStart: Date { WorkoutPlanService.startOfWeek() }

    private var currentWeight: Double? {
        healthContext?.healthKitService.currentWeight
            ?? weightEntries.first?.weight
            ?? healthContext?.currentWeight
    }

    private var combinedWeightHistory: [WeightRecord] {
        var records = healthContext?.healthKitService.dailyWeights ?? []
        for entry in weightEntries {
            records.append(WeightRecord(date: entry.date, weight: entry.weight))
        }
        let grouped = Dictionary(grouping: records) { Calendar.current.startOfDay(for: $0.date) }
        return grouped.compactMap { $0.value.first }.sorted { $0.date > $1.date }
    }

    var body: some View {
        NavigationStack {
            List {
                if !weeklyNutritionDaysCache.isEmpty {
                    Section("本周营养目标") {
                        VStack(alignment: .leading, spacing: 8) {
                            if weekEntriesCache.count > 0 {
                                Text("本周 \(weekEntriesCache.count) 场训练 · 全周按排课区分训练日/休息日")
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(Theme.adaptiveAccent(colorScheme))
                            }
                            WeeklyNutritionStrip(
                                days: weeklyNutritionDaysCache,
                                compact: true,
                                baselineCalories: healthContext?.baselineDailyBudget
                            )
                            if let note = healthContext?.nutritionAdjustmentNote {
                                Text("今日：\(note)")
                                    .font(.caption)
                                    .foregroundStyle(Theme.adaptiveTextSecondary(colorScheme))
                            }
                            Text("今日摄入与蛋白/碳水/脂肪进度见首页仪表盘。")
                                .font(.caption2)
                                .foregroundStyle(Theme.adaptiveTextSecondary(colorScheme))
                        }
                        .listRowBackground(Color.clear)
                    }
                }

                if let info = healthContext?.cyclePhaseInfo, info.phase != .unknown {
                    Section("周期关怀") {
                        CycleTipsCard(phaseInfo: info, compact: true)
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
                    }
                }

                Section("记录") {
                    NavigationLink {
                        FoodInputView()
                    } label: {
                        Label("记录饮食", systemImage: "plus.circle.fill")
                    }

                    NavigationLink {
                        HistoryView()
                    } label: {
                        Label("饮食历史", systemImage: "calendar")
                    }
                }

                Section("顾问") {
                    NavigationLink {
                        AIAdvisorView(
                            foodEntries: allEntries,
                            userGoal: currentGoal,
                            currentWeight: currentWeight,
                            weightHistory: combinedWeightHistory
                        )
                    } label: {
                        Label("AI 营养顾问", systemImage: "sparkles")
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .cycleThemedPageBackground()
            .navigationTitle("营养")
            .task { await refreshContext() }
            .onAppear { reloadWeekNutritionCache() }
        }
    }

    private func reloadWeekNutritionCache() {
        weekEntriesCache = WorkoutPlanService.entriesForWeek(weekStart, modelContext: modelContext)
        if let prefs = workoutPreferences.first,
           WorkoutNutritionPlanner.hasActivePlan(prefs) {
            weeklyNutritionDaysCache = WorkoutNutritionPlanner.weeklyNutritionDays(
                prefs: prefs,
                trainingWeekdays: weekEntriesCache.map(\.dayOfWeek),
                weekStart: weekStart,
                baselineCalories: healthContext?.baselineDailyBudget
            )
        } else {
            weeklyNutritionDaysCache = []
        }
    }

    private func refreshContext() async {
        let isTrainingDay = WorkoutPlanService.hasPlannedSession(modelContext: modelContext)
        await healthContext?.refresh(
            foodEntries: allEntries,
            goals: goals,
            weightEntries: weightEntries,
            cycleProfiles: cycleProfiles,
            reports: reports,
            riskFlags: riskFlags,
            todos: todos,
            checkupPlans: checkupPlans,
            workoutPreferences: workoutPreferences.first,
            isTrainingDayToday: isTrainingDay
        )
        reloadWeekNutritionCache()
    }
}

#Preview {
    WeightLossTabView()
        .modelContainer(for: [FoodEntry.self, UserGoal.self, WeightEntry.self, CycleProfile.self], inMemory: true)
        .healthContext(UnifiedHealthContext())
}
