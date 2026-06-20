import SwiftUI

import SwiftData



/// 减脂 Tab：整合饮食记录、目标与历史

/// @author jiali.qiu

struct WeightLossTabView: View {

    @Environment(\.healthContext) private var healthContext

    @StateObject private var healthKitService = HealthKitService()



    @Query(sort: \FoodEntry.createdAt, order: .reverse) private var allEntries: [FoodEntry]

    @Query private var goals: [UserGoal]

    @Query(sort: \WeightEntry.date, order: .reverse) private var weightEntries: [WeightEntry]



    private var currentGoal: UserGoal? { goals.first }



    private var currentWeight: Double? {

        healthKitService.currentWeight ?? weightEntries.first?.weight ?? healthContext?.currentWeight

    }



    private var combinedWeightHistory: [WeightRecord] {

        var records = healthKitService.dailyWeights

        for entry in weightEntries {

            records.append(WeightRecord(date: entry.date, weight: entry.weight))

        }

        let grouped = Dictionary(grouping: records) { Calendar.current.startOfDay(for: $0.date) }

        return grouped.compactMap { $0.value.first }.sorted { $0.date > $1.date }

    }



    var body: some View {

        NavigationStack {

            List {

                NavigationLink {

                    FoodInputView()

                } label: {

                    Label("记录饮食", systemImage: "plus.circle.fill")

                }



                NavigationLink {

                    GoalsView()

                } label: {

                    Label("减脂目标", systemImage: "target")

                }



                NavigationLink {

                    HistoryView()

                } label: {

                    Label("饮食历史", systemImage: "calendar")

                }



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

            .navigationTitle("体态")

            .task {

                await healthKitService.requestAuthorization()

            }

        }

    }

}



#Preview {

    WeightLossTabView()

        .modelContainer(for: [FoodEntry.self, UserGoal.self, WeightEntry.self], inMemory: true)

        .healthContext(UnifiedHealthContext())

}

