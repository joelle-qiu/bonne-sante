import SwiftUI
import SwiftData

struct GoalsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.healthContext) private var healthContext
    @Environment(\.colorScheme) private var colorScheme
    @Query private var goals: [UserGoal]
    @Query(sort: \WeightEntry.date, order: .reverse) private var manualWeightEntries: [WeightEntry]
    @Query private var settings: [UserSettings]

    @State private var showingGoalSettings = false
    @State private var showingWeightEntry = false

    private var currentGoal: UserGoal? { goals.first }

    private var weightUnit: WeightUnit {
        settings.first?.preferredWeightUnit ?? .kg
    }

    private func formatWeight(_ kgValue: Double) -> String {
        weightUnit.format(kgValue)
    }

    // Combine HealthKit and manual weight data
    private var combinedWeightHistory: [WeightRecord] {
        var allRecords: [WeightRecord] = []

        allRecords.append(contentsOf: healthContext?.healthKitService.dailyWeights ?? [])

        for entry in manualWeightEntries {
            allRecords.append(WeightRecord(date: entry.date, weight: entry.weight))
        }

        let grouped = Dictionary(grouping: allRecords) { record in
            Calendar.current.startOfDay(for: record.date)
        }

        return grouped.map { (_, records) in
            records.first!
        }.sorted { $0.date < $1.date }
    }

    private var currentWeight: Double? {
        healthContext?.currentWeight
            ?? manualWeightEntries.first?.weight
            ?? healthContext?.healthKitService.currentWeight
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    WeightChartView(
                        weightHistory: combinedWeightHistory,
                        targetWeight: currentGoal?.targetWeight,
                        weightUnit: weightUnit
                    )

                    if let goal = currentGoal {
                        goalProgressCard(goal)
                        bodyCompositionCard(goal)
                    } else {
                        noGoalCard
                    }
                }
                .padding()
            }
            .cycleThemedPageBackground()
            .navigationTitle("目标")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showingWeightEntry = true
                    } label: {
                        Image(systemName: "plus.circle")
                        Text("记录体重")
                    }
                    .font(.caption)
                }

                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 12) {
                        Menu {
                            ForEach(WeightUnit.allCases, id: \.self) { unit in
                                Button {
                                    setWeightUnit(unit)
                                } label: {
                                    HStack {
                                        Text(unit.displayName)
                                        if unit == weightUnit {
                                            Image(systemName: "checkmark")
                                        }
                                    }
                                }
                            }
                        } label: {
                            Text(weightUnit.shortName)
                                .font(.caption)
                                .fontWeight(.medium)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.blue.opacity(0.15))
                                .clipShape(Capsule())
                        }

                        Button {
                            showingGoalSettings = true
                        } label: {
                            Image(systemName: "gearshape")
                        }
                    }
                }
            }
            .sheet(isPresented: $showingGoalSettings) {
                GoalSettingView(passedCurrentWeight: currentWeight)
            }
            .sheet(isPresented: $showingWeightEntry) {
                ManualWeightEntryView()
            }
            .task {
                await healthContext?.healthKitService.requestAuthorization()
                await healthContext?.healthKitService.fetchWeightHistory()
                await healthContext?.healthKitService.fetchBodyProfile()
                syncUserGoalFromHealthKit()
            }
            .refreshable {
                await healthContext?.healthKitService.fetchWeightHistory()
                await healthContext?.healthKitService.fetchBodyProfile()
                syncUserGoalFromHealthKit()
            }
        }
    }

    private func setWeightUnit(_ unit: WeightUnit) {
        if let existing = settings.first {
            existing.preferredWeightUnit = unit
        } else {
            let newSettings = UserSettings(weightUnit: unit)
            modelContext.insert(newSettings)
        }
    }

    private func syncUserGoalFromHealthKit() {
        guard let goal = currentGoal,
              let profile = healthContext?.healthKitService.bodyProfile else { return }
        goal.mergeHealthKitProfile(profile, modelContext: modelContext)
    }

    private var noGoalCard: some View {
        VStack(spacing: 16) {
            Image(systemName: "target")
                .fixedFont(size: 48)
                .foregroundStyle(.secondary)

            Text("还没有设置目标")
                .font(.headline)

            Text("设置目标体重，获取个性化的每日热量建议")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button("设置目标") {
                showingGoalSettings = true
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.1), radius: 5, x: 0, y: 2)
    }

    private func goalProgressCard(_ goal: UserGoal) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("目标进度")
                    .font(.headline)
                Spacer()
                if let targetDate = goal.targetDate {
                    let daysLeft = Calendar.current.dateComponents([.day], from: Date(), to: targetDate).day ?? 0
                    Text("还剩 \(daysLeft) 天")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let weight = currentWeight {
                let startWeight = combinedWeightHistory.first?.weight ?? weight
                let totalToLose = startWeight - goal.targetWeight
                let lost = startWeight - weight
                let progress = totalToLose > 0 ? min(lost / totalToLose, 1.0) : 1.0

                VStack(spacing: 8) {
                    ProgressView(value: max(progress, 0))
                        .tint(.green)

                    HStack {
                        VStack(alignment: .leading) {
                            Text("当前")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(formatWeight(weight))
                                .font(.title2)
                                .fontWeight(.bold)
                        }

                        Spacer()

                        VStack {
                            Text("已减")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(formatWeight(max(lost, 0)))
                                .font(.title2)
                                .fontWeight(.bold)
                                .foregroundStyle(.green)
                        }

                        Spacer()

                        VStack(alignment: .trailing) {
                            Text("目标")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(formatWeight(goal.targetWeight))
                                .font(.title2)
                                .fontWeight(.bold)
                                .foregroundStyle(.blue)
                        }
                    }
                }
            } else {
                VStack(spacing: 8) {
                    Text("暂无体重数据")
                        .foregroundStyle(.secondary)
                    Button("手动记录体重") {
                        showingWeightEntry = true
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.1), radius: 5, x: 0, y: 2)
    }

    @ViewBuilder
    private func bodyCompositionCard(_ goal: UserGoal) -> some View {
        let profile = healthContext?.healthKitService.bodyProfile ?? .empty
        let bodyFat = profile.bodyFatPercent ?? goal.currentBodyFat
        let leanMass = profile.leanBodyMassKg ?? goal.currentLeanBodyMassKg
        let weight = currentWeight

        if bodyFat == nil && leanMass == nil && goal.targetBodyFat == nil && goal.effectiveTargetLeanMassKg == nil {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 14) {
                Text("体成分")
                    .font(.headline)

                if let weight {
                    compositionRow(title: "体重", value: formatWeight(weight))
                }

                if let bodyFat {
                    compositionRow(title: "体脂率", value: String(format: "%.1f%%", bodyFat))
                    if let weight {
                        compositionRow(
                            title: "脂肪量",
                            value: String(format: "%.1f kg", weight * bodyFat / 100)
                        )
                    }
                    if let target = goal.targetBodyFat {
                        compositionRow(
                            title: "目标体脂",
                            value: String(format: "%.1f%%", target),
                            accent: .blue
                        )
                    }
                }

                if let leanMass {
                    compositionRow(title: "去脂体重", value: String(format: "%.1f kg", leanMass))
                    if let target = goal.effectiveTargetLeanMassKg, goal.targetBodyFat != nil {
                        compositionRow(
                            title: "目标去脂体重",
                            value: String(format: "%.1f kg", target),
                            accent: Theme.link(colorScheme)
                        )
                    }
                }

                if bodyFat == nil && leanMass == nil {
                    Text("在 Apple 健康中记录体脂/去脂体重后，或于目标设置中手动填写。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if profile.bodyFatPercent != nil || profile.leanBodyMassKg != nil {
                    Label("数据来自 Apple 健康", systemImage: "heart.text.square")
                        .font(.caption2)
                        .foregroundStyle(.green)
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.cardBackground(colorScheme))
            .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadiusCard))
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.25 : 0.1), radius: 5, x: 0, y: 2)
        }
    }

    private func compositionRow(title: String, value: String, accent: Color = .primary) -> some View {
        HStack {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(accent)
        }
    }
}

#Preview {
    GoalsView()
        .modelContainer(for: [UserGoal.self, WeightEntry.self, UserSettings.self], inMemory: true)
        .healthContext(UnifiedHealthContext())
}
