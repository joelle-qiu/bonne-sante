import SwiftUI
import SwiftData

struct GoalSettingView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.healthContext) private var healthContext
    @Environment(\.dismiss) private var dismiss
    @Query private var goals: [UserGoal]
    @Query private var settings: [UserSettings]
    @Query(sort: \WeightEntry.date, order: .reverse) private var weightEntries: [WeightEntry]

    /// 当前体重（HealthKit 优先，其次手动记录或父视图传入）
    var passedCurrentWeight: Double?

    private var currentWeight: Double? {
        healthContext?.healthKitService.currentWeight
            ?? passedCurrentWeight
            ?? weightEntries.first?.weight
    }

    @State private var targetWeight: Double = 65
    @State private var height: Double = 170
    @State private var age: Int = 30
    @State private var gender: String = "female"
    @State private var activityLevel: String = "moderate"
    @State private var hasTargetDate: Bool = false
    @State private var targetDate: Date = Date().addingTimeInterval(86400 * 90)
    @State private var initialized = false
    @State private var healthKitSyncedFields: Set<HealthProfileField> = []

    var currentGoal: UserGoal? { goals.first }

    private var weightUnit: WeightUnit {
        settings.first?.preferredWeightUnit ?? .kg
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    bodyInfoRows
                } header: {
                    Text("身体信息")
                } footer: {
                    if !healthKitSyncedFields.isEmpty {
                        Label(
                            "已从 Apple 健康同步：\(healthKitSyncedFields.map(\.label).joined(separator: "、"))，可手动修改",
                            systemImage: "heart.text.square"
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }

                Section("目标设置") {
                    if let weight = currentWeight {
                        HStack {
                            Text("当前体重")
                            Spacer()
                            Text(weightUnit.format(weight))
                                .foregroundStyle(.secondary)
                        }
                    }

                    HStack {
                        Text("目标体重")
                        Spacer()
                        TextField(weightUnit.shortName, value: $targetWeight, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                        Text(weightUnit.shortName)
                            .foregroundStyle(.secondary)
                    }

                    if hasTargetDate {
                        DatePicker("目标日期", selection: $targetDate, in: Date()..., displayedComponents: .date)

                        Button(role: .destructive) {
                            hasTargetDate = false
                        } label: {
                            HStack {
                                Image(systemName: "xmark.circle.fill")
                                Text("清除目标日期")
                            }
                        }
                    } else {
                        Button {
                            hasTargetDate = true
                            targetDate = Date().addingTimeInterval(86400 * 90)
                        } label: {
                            HStack {
                                Image(systemName: "calendar.badge.plus")
                                Text("设置目标日期")
                            }
                        }
                    }
                }

                Section("活动水平") {
                    Picker("日常活动量", selection: $activityLevel) {
                        Text("久坐（很少运动）").tag("sedentary")
                        Text("轻度（每周1-3次运动）").tag("light")
                        Text("中度（每周3-5次运动）").tag("moderate")
                        Text("活跃（每周6-7次运动）").tag("active")
                        Text("非常活跃（运动员/体力劳动）").tag("very_active")
                    }
                    .pickerStyle(.navigationLink)
                }

                Section {
                    calorieRecommendation
                }

                Section {
                    Button("保存目标") {
                        saveGoal()
                    }
                    .frame(maxWidth: .infinity)
                    .foregroundStyle(.blue)
                }
            }
            .navigationTitle("设置目标")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
                    }
                }
            }
            .task {
                loadExistingGoal()
                await syncFromHealthKitIfNeeded()
            }
        }
    }

    @ViewBuilder
    private var bodyInfoRows: some View {
        HStack {
            Text("身高")
            Spacer()
            TextField("cm", value: $height, format: .number)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 80)
            Text("cm")
                .foregroundStyle(.secondary)
        }

        HStack {
            Text("年龄")
            Spacer()
            TextField("岁", value: $age, format: .number)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 80)
            Text("岁")
                .foregroundStyle(.secondary)
        }

        Picker("性别", selection: $gender) {
            Text("男").tag("male")
            Text("女").tag("female")
        }
    }

    private var calorieRecommendation: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("建议每日摄入")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            let targetWeightInKg = weightUnit.toKg(targetWeight)

            let goal = UserGoal(
                targetWeight: targetWeightInKg,
                height: height,
                age: age,
                gender: gender,
                activityLevel: activityLevel,
                targetDate: hasTargetDate ? targetDate : nil
            )

            let weightForCalc = currentWeight ?? (targetWeightInKg + 5)
            let isEstimated = currentWeight == nil
            let recommended = goal.recommendedDailyCalories(currentWeight: weightForCalc)
            let tdee = goal.calculateTDEE(currentWeight: weightForCalc)

            HStack {
                VStack {
                    Text("\(Int(recommended))")
                        .font(.title)
                        .fontWeight(.bold)
                        .foregroundStyle(.green)
                    Text("推荐摄入")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                VStack {
                    Text("\(Int(tdee))")
                        .font(.title)
                        .fontWeight(.bold)
                        .foregroundStyle(.orange)
                    Text("每日消耗")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                VStack {
                    Text("\(Int(tdee - recommended))")
                        .font(.title)
                        .fontWeight(.bold)
                        .foregroundStyle(.blue)
                    Text("热量缺口")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if isEstimated {
                Text("* 基于预估当前体重 \(weightUnit.format(weightForCalc)) 计算")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            } else {
                Text("* 基于当前体重 \(weightUnit.format(weightForCalc)) 计算")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func loadExistingGoal() {
        guard !initialized else { return }
        initialized = true

        if let goal = currentGoal {
            let convertedWeight = weightUnit.fromKg(goal.targetWeight)
            targetWeight = (convertedWeight * 10).rounded() / 10
            height = goal.height
            age = goal.age
            gender = goal.gender
            activityLevel = goal.activityLevel
            if let date = goal.targetDate {
                hasTargetDate = true
                targetDate = date
            }
        } else {
            targetWeight = weightUnit == .lb ? 143.0 : 65.0
        }
    }

    private func syncFromHealthKitIfNeeded() async {
        guard currentGoal == nil else { return }

        if healthContext?.healthKitService.isHealthKitAvailable == true {
            await healthContext?.healthKitService.fetchBodyProfile()
        }

        guard let profile = healthContext?.healthKitService.bodyProfile else { return }

        var synced = Set<HealthProfileField>()

        if let heightCm = profile.heightCm, heightCm > 50, heightCm < 250 {
            height = (heightCm * 10).rounded() / 10
            synced.insert(.height)
        }

        if let profileAge = profile.age, (16...100).contains(profileAge) {
            age = profileAge
            synced.insert(.age)
        }

        if let profileGender = profile.gender {
            gender = profileGender
            synced.insert(.gender)
        }

        if let weightKg = profile.currentWeightKg ?? currentWeight {
            let converted = weightUnit.fromKg(weightKg)
            let rounded = (converted * 10).rounded() / 10
            // 无目标时，默认目标体重略低于当前体重
            if targetWeight == (weightUnit == .lb ? 143.0 : 65.0) {
                let suggested = weightUnit == .lb
                    ? max(rounded - 6.6, 88)
                    : max(rounded - 3, 40)
                targetWeight = (suggested * 10).rounded() / 10
            }
            synced.insert(.currentWeight)
        }

        healthKitSyncedFields = synced
    }

    private func saveGoal() {
        let roundedTargetWeight = (targetWeight * 10).rounded() / 10
        let targetWeightInKg = weightUnit.toKg(roundedTargetWeight)

        if let existing = currentGoal {
            existing.targetWeight = targetWeightInKg
            existing.height = height
            existing.age = age
            existing.gender = gender
            existing.activityLevel = activityLevel
            existing.targetDate = hasTargetDate ? targetDate : nil
            existing.updatedAt = Date()
        } else {
            let goal = UserGoal(
                targetWeight: targetWeightInKg,
                height: height,
                age: age,
                gender: gender,
                activityLevel: activityLevel,
                targetDate: hasTargetDate ? targetDate : nil
            )
            modelContext.insert(goal)
        }

        try? modelContext.save()
        dismiss()
    }
}

/// 可从 预填字段标识
private enum HealthProfileField: Hashable {
    case height
    case age
    case gender
    case currentWeight

    var label: String {
        switch self {
        case .height: return "身高"
        case .age: return "年龄"
        case .gender: return "性别"
        case .currentWeight: return "当前体重"
        }
    }
}

#Preview {
    GoalSettingView(passedCurrentWeight: 70.0)
        .modelContainer(for: [UserGoal.self, FoodEntry.self, UserSettings.self, WeightEntry.self], inMemory: true)
        .healthContext(UnifiedHealthContext())
}
