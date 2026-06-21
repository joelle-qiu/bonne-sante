import SwiftUI
import SwiftData

/// 营养 Tab：饮食记录、历史与 AI 顾问
/// @author jiali.qiu
struct WeightLossTabView: View {
    @Environment(\.healthContext) private var healthContext

    @Query(sort: \FoodEntry.createdAt, order: .reverse) private var allEntries: [FoodEntry]
    @Query private var goals: [UserGoal]
    @Query(sort: \WeightEntry.date, order: .reverse) private var weightEntries: [WeightEntry]
    @Query private var cycleProfiles: [CycleProfile]
    @Query(sort: \Report.importDate, order: .reverse) private var reports: [Report]
    @Query(filter: #Predicate<RiskFlag> { !$0.isResolved }) private var riskFlags: [RiskFlag]
    @Query(sort: \TodoItem.dueDate) private var todos: [TodoItem]
    @Query private var checkupPlans: [CheckupPlan]

    private var currentGoal: UserGoal? { goals.first }

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
            .navigationTitle("营养")
            .task { await refreshContext() }
        }
    }

    private func refreshContext() async {
        await healthContext?.refresh(
            foodEntries: allEntries,
            goals: goals,
            weightEntries: weightEntries,
            cycleProfiles: cycleProfiles,
            reports: reports,
            riskFlags: riskFlags,
            todos: todos,
            checkupPlans: checkupPlans
        )
    }
}

#Preview {
    WeightLossTabView()
        .modelContainer(for: [FoodEntry.self, UserGoal.self, WeightEntry.self, CycleProfile.self], inMemory: true)
        .healthContext(UnifiedHealthContext())
}
