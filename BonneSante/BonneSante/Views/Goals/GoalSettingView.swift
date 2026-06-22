import SwiftUI
import SwiftData

struct GoalSettingView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.healthContext) private var healthContext
    @Environment(\.colorScheme) private var colorScheme
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

    @State private var targetWeight: Double = 50
    @State private var height: Double = 170
    @State private var age: Int = 28
    @State private var gender: String = "female"
    @State private var activityLevel: String = "moderate"
    @State private var hasTargetDate: Bool = false
    @State private var targetDate: Date = Date().addingTimeInterval(86400 * 90)
    @State private var hasTargetBodyFat: Bool = false
    @State private var targetBodyFat: Double = 22
    @State private var displayCurrentBodyFat: Double?
    @State private var displayCurrentLeanMassKg: Double?
    @State private var initialized = false
    @State private var healthKitSyncedFields: Set<HealthProfileField> = []
    @State private var ageMissingInHealthKit = false

    var currentGoal: UserGoal? { goals.first }

    private var weightUnit: WeightUnit {
        settings.first?.preferredWeightUnit ?? .kg
    }

    /// 由目标体重 + 目标体脂率推导的去脂体重
    private var derivedTargetLeanMassKg: Double? {
        guard hasTargetBodyFat else { return nil }
        let weightKg = weightUnit.toKg(targetWeight)
        return weightKg * (1 - targetBodyFat / 100)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    bodyInfoRows
                } header: {
                    Text("身体信息")
                        .foregroundStyle(Theme.adaptiveTextSecondary(colorScheme))
                } footer: {
                    if !healthKitSyncedFields.isEmpty {
                        Label(
                            "已从 Apple 健康同步：\(healthKitSyncedFields.map(\.label).joined(separator: "、"))，可手动修改",
                            systemImage: "heart.text.square"
                        )
                        .font(.caption)
                        .foregroundStyle(Theme.adaptiveTextSecondary(colorScheme))
                    }
                    if ageMissingInHealthKit {
                        Text("Apple 健康未读取到出生日期。请在 iPhone「健康 → 浏览 → 个人资料信息」填写生日，返回本页下拉刷新。")
                            .font(.caption)
                            .foregroundStyle(Theme.adaptiveWarning(colorScheme))
                    }
                }

                Section {
                    goalSettingRows
                } header: {
                    Text("目标设置")
                        .foregroundStyle(Theme.adaptiveTextSecondary(colorScheme))
                }

                Section {
                    bodyCompositionCurrentRows
                } header: {
                    Text("体成分（Apple 健康）")
                        .foregroundStyle(Theme.adaptiveTextSecondary(colorScheme))
                } footer: {
                    Text("体脂率、去脂体重来自 Apple 健康最近记录（PICOOC 等体脂秤写入）。若体脂显示异常，会用体重与去脂体重自动校正。")
                        .font(.caption)
                        .foregroundStyle(Theme.adaptiveTextTertiary(colorScheme))
                }

                Section {
                    bodyCompositionGoalRows
                } header: {
                    Text("体成分目标")
                        .foregroundStyle(Theme.adaptiveTextSecondary(colorScheme))
                } footer: {
                    Text("目标去脂体重 = 目标体重 × (1 − 目标体脂率)，无需单独填写。")
                        .font(.caption)
                        .foregroundStyle(Theme.adaptiveTextTertiary(colorScheme))
                }

                Section {
                    Picker("日常活动量", selection: $activityLevel) {
                        Text("久坐（很少运动）").tag("sedentary")
                        Text("轻度（每周1-3次运动）").tag("light")
                        Text("中度（每周3-5次运动）").tag("moderate")
                        Text("活跃（每周6-7次运动）").tag("active")
                        Text("非常活跃（运动员/体力劳动）").tag("very_active")
                    }
                    .pickerStyle(.navigationLink)
                } header: {
                    Text("活动水平")
                        .foregroundStyle(Theme.adaptiveTextSecondary(colorScheme))
                }

                Section {
                    calorieRecommendation
                }

                Section {
                    Button("保存目标") {
                        saveGoal()
                    }
                    .frame(maxWidth: .infinity)
                    .foregroundStyle(Theme.link(colorScheme))
                }
            }
            .morandiFormSurface()
            .cycleThemedPageBackground()
            .navigationTitle("设置目标")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
                    }
                    .foregroundStyle(Theme.adaptiveTextSecondary(colorScheme))
                }
            }
            .task {
                loadExistingGoal()
                await syncProfileFromHealthKit()
            }
            .refreshable {
                await syncProfileFromHealthKit()
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
                .foregroundStyle(Theme.adaptiveTextSecondary(colorScheme))
        }

        HStack {
            Text("年龄")
            Spacer()
            TextField("岁", value: $age, format: .number)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 80)
            Text("岁")
                .foregroundStyle(Theme.adaptiveTextSecondary(colorScheme))
        }

        Picker("性别", selection: $gender) {
            Text("男").tag("male")
            Text("女").tag("female")
        }
    }

    @ViewBuilder
    private var goalSettingRows: some View {
        if let weight = currentWeight {
            HStack {
                Text("当前体重")
                Spacer()
                Text(weightUnit.format(weight))
                    .foregroundStyle(Theme.adaptiveTextSecondary(colorScheme))
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
                .foregroundStyle(Theme.adaptiveTextSecondary(colorScheme))
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

    @ViewBuilder
    private var bodyCompositionCurrentRows: some View {
        if let bodyFat = displayCurrentBodyFat {
            HStack {
                Text("当前体脂率")
                Spacer()
                Text(String(format: "%.1f%%", bodyFat))
                    .foregroundStyle(Theme.adaptiveTextSecondary(colorScheme))
            }
            if let weight = currentWeight {
                let fatKg = weight * bodyFat / 100
                HStack {
                    Text("估算脂肪量")
                    Spacer()
                    Text(String(format: "%.1f kg", fatKg))
                        .foregroundStyle(Theme.adaptiveTextSecondary(colorScheme))
                }
            }
        } else {
            HStack {
                Text("当前体脂率")
                Spacer()
                Text("暂无数据")
                    .foregroundStyle(Theme.adaptiveTextTertiary(colorScheme))
            }
        }

        if let lean = displayCurrentLeanMassKg {
            HStack {
                Text("当前去脂体重")
                Spacer()
                Text(String(format: "%.1f kg", lean))
                    .foregroundStyle(Theme.adaptiveTextSecondary(colorScheme))
            }
        } else {
            HStack {
                Text("当前去脂体重")
                Spacer()
                Text("暂无数据")
                    .foregroundStyle(Theme.adaptiveTextTertiary(colorScheme))
            }
        }
    }

    @ViewBuilder
    private var bodyCompositionGoalRows: some View {
        if hasTargetBodyFat {
            HStack {
                Text("目标体脂率")
                Spacer()
                TextField("%", value: $targetBodyFat, format: .number)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 64)
                Text("%")
                    .foregroundStyle(Theme.adaptiveTextSecondary(colorScheme))
            }

            if let lean = derivedTargetLeanMassKg {
                HStack {
                    Text("推导目标去脂体重")
                    Spacer()
                    Text(String(format: "%.1f kg", lean))
                        .foregroundStyle(Theme.adaptiveTextSecondary(colorScheme))
                }
            }

            Button(role: .destructive) {
                hasTargetBodyFat = false
            } label: {
                Text("清除目标体脂")
            }
        } else {
            Button {
                hasTargetBodyFat = true
                if let current = displayCurrentBodyFat {
                    targetBodyFat = max(current - 3, 12)
                }
            } label: {
                Label("设置目标体脂率", systemImage: "percent")
            }
        }
    }

    private var calorieRecommendation: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("建议每日摄入")
                .font(.subheadline)
                .foregroundStyle(Theme.adaptiveTextSecondary(colorScheme))

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
                        .foregroundStyle(Theme.energyActive(colorScheme))
                    Text("推荐摄入")
                        .font(.caption)
                        .foregroundStyle(Theme.adaptiveTextSecondary(colorScheme))
                }

                Spacer()

                VStack {
                    Text("\(Int(tdee))")
                        .font(.title)
                        .fontWeight(.bold)
                        .foregroundStyle(Theme.energyConsumed(colorScheme))
                    Text("每日消耗")
                        .font(.caption)
                        .foregroundStyle(Theme.adaptiveTextSecondary(colorScheme))
                }

                Spacer()

                VStack {
                    Text("\(Int(tdee - recommended))")
                        .font(.title)
                        .fontWeight(.bold)
                        .foregroundStyle(Theme.link(colorScheme))
                    Text("热量缺口")
                        .font(.caption)
                        .foregroundStyle(Theme.adaptiveTextSecondary(colorScheme))
                }
            }

            if isEstimated {
                Text("* 基于预估当前体重 \(weightUnit.format(weightForCalc)) 计算")
                    .font(.caption2)
                    .foregroundStyle(Theme.adaptiveTextTertiary(colorScheme))
            } else {
                Text("* 基于当前体重 \(weightUnit.format(weightForCalc)) 计算")
                    .font(.caption2)
                    .foregroundStyle(Theme.adaptiveTextTertiary(colorScheme))
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
            if let bf = goal.targetBodyFat {
                hasTargetBodyFat = true
                targetBodyFat = bf
            }
            displayCurrentBodyFat = goal.currentBodyFat
            displayCurrentLeanMassKg = goal.currentLeanBodyMassKg
        } else {
            gender = "female"
            targetWeight = weightUnit.fromKg(UserGoal.defaultTargetWeightKg(gender: gender))
        }
    }

    /// 每次打开均从 Apple 健康同步档案（含年龄），不仅限于首次创建目标
    private func syncProfileFromHealthKit() async {
        guard healthContext?.healthKitService.isHealthKitAvailable == true else { return }
        await healthContext?.healthKitService.fetchBodyProfile()
        guard let profile = healthContext?.healthKitService.bodyProfile else { return }

        var synced = Set<HealthProfileField>()

        if let heightCm = profile.heightCm, heightCm > 50, heightCm < 250 {
            height = (heightCm * 10).rounded() / 10
            synced.insert(.height)
        }

        if let profileAge = profile.age, (16...100).contains(profileAge) {
            age = profileAge
            synced.insert(.age)
            ageMissingInHealthKit = false
        } else {
            ageMissingInHealthKit = true
        }

        if let profileGender = profile.gender {
            gender = profileGender
            synced.insert(.gender)
        }

        if let bodyFat = profile.bodyFatPercent {
            displayCurrentBodyFat = bodyFat
            synced.insert(.bodyFat)
        }

        if let lean = profile.leanBodyMassKg, lean > 0 {
            displayCurrentLeanMassKg = (lean * 10).rounded() / 10
            synced.insert(.leanMass)
        }

        if currentGoal == nil,
           gender != "female",
           let weightKg = profile.currentWeightKg ?? currentWeight {
            let converted = weightUnit.fromKg(weightKg)
            let rounded = (converted * 10).rounded() / 10
            let defaultTarget = weightUnit.fromKg(UserGoal.defaultTargetWeightKg(gender: gender))
            if abs(targetWeight - defaultTarget) < 0.01 {
                let suggested = weightUnit == .lb
                    ? max(rounded - 6.6, 88)
                    : max(rounded - 3, 40)
                targetWeight = (suggested * 10).rounded() / 10
            }
            synced.insert(.currentWeight)
        }

        if let goal = currentGoal {
            if goal.mergeHealthKitProfile(profile, modelContext: modelContext) {
                age = goal.age
                height = goal.height
                gender = goal.gender
                displayCurrentBodyFat = goal.currentBodyFat
                displayCurrentLeanMassKg = goal.currentLeanBodyMassKg
            }
        }

        healthKitSyncedFields = synced
    }

    private func saveGoal() {
        let roundedTargetWeight = (targetWeight * 10).rounded() / 10
        let targetWeightInKg = weightUnit.toKg(roundedTargetWeight)
        let derivedLean = hasTargetBodyFat ? targetWeightInKg * (1 - targetBodyFat / 100) : nil

        if let existing = currentGoal {
            existing.targetWeight = targetWeightInKg
            existing.height = height
            existing.age = age
            existing.gender = gender
            existing.activityLevel = activityLevel
            existing.targetDate = hasTargetDate ? targetDate : nil
            existing.currentBodyFat = displayCurrentBodyFat
            existing.currentLeanBodyMassKg = displayCurrentLeanMassKg
            existing.targetBodyFat = hasTargetBodyFat ? targetBodyFat : nil
            existing.targetLeanBodyMassKg = derivedLean
            existing.updatedAt = Date()
        } else {
            let goal = UserGoal(
                targetWeight: targetWeightInKg,
                height: height,
                age: age,
                gender: gender,
                activityLevel: activityLevel,
                targetDate: hasTargetDate ? targetDate : nil,
                targetBodyFat: hasTargetBodyFat ? targetBodyFat : nil,
                currentBodyFat: displayCurrentBodyFat,
                targetLeanBodyMassKg: derivedLean,
                currentLeanBodyMassKg: displayCurrentLeanMassKg
            )
            modelContext.insert(goal)
        }

        try? modelContext.save()
        dismiss()
    }
}

/// 可从 HealthKit 预填字段标识
private enum HealthProfileField: Hashable {
    case height
    case age
    case gender
    case currentWeight
    case bodyFat
    case leanMass

    var label: String {
        switch self {
        case .height: return "身高"
        case .age: return "年龄"
        case .gender: return "性别"
        case .currentWeight: return "当前体重"
        case .bodyFat: return "体脂率"
        case .leanMass: return "去脂体重"
        }
    }
}

#Preview {
    GoalSettingView(passedCurrentWeight: 70.0)
        .modelContainer(for: [UserGoal.self, FoodEntry.self, UserSettings.self, WeightEntry.self], inMemory: true)
        .healthContext(UnifiedHealthContext())
}
