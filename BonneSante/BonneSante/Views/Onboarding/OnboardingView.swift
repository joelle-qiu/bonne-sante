import SwiftUI
import SwiftData

/// 首次启动引导：欢迎 → HealthKit → AI 配置 → 减脂目标
/// @author jiali.qiu
struct OnboardingView: View {
    @Environment(\.healthContext) private var healthContext
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme

    let onComplete: () -> Void

    @State private var step = 0
    @State private var healthKitRequested = false
    @State private var deepSeekConfigured = APIKeyManager.isDeepSeekConfigured

    // 减脂目标
    @State private var currentWeight: Double = 58
    @State private var targetWeight: Double = 50
    @State private var height: Double = 165
    @State private var age: Int = 28
    @State private var gender: String = "female"
    @State private var targetDate = Calendar.current.date(byAdding: .month, value: 3, to: Date()) ?? Date()
    @State private var healthKitSyncedFields: Set<String> = []

    private let totalSteps = 4

    var body: some View {
        VStack(spacing: 0) {
            progressBar
                .padding(.horizontal, Theme.horizontalPadding)
                .padding(.top, 16)

            TabView(selection: $step) {
                welcomeStep.tag(0)
                healthKitStep.tag(1)
                aiStep.tag(2)
                goalStep.tag(3)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(.easeInOut, value: step)

            bottomBar
                .padding(.horizontal, Theme.horizontalPadding)
                .padding(.bottom, 24)
        }
        .background(Theme.pageBackground(colorScheme))
    }

    // MARK: - Progress

    private var progressBar: some View {
        HStack(spacing: 6) {
            ForEach(0..<totalSteps, id: \.self) { index in
                Capsule()
                    .fill(index <= step ? Theme.brandPrimary(colorScheme) : Color(.systemGray4))
                    .frame(height: 4)
            }
        }
    }

    // MARK: - Steps

    private var welcomeStep: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "heart.text.clipboard.fill")
                .fixedFont(size: 64)
                .foregroundStyle(Theme.brandPrimary(colorScheme))
            Text("欢迎使用 Bonne-Santé")
                .font(.title.bold())
            Text("你的女性专属健康助手\n整合减脂计划、周期关怀与 AI 营养顾问")
                .font(.body)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .padding(Theme.horizontalPadding)
    }

    private var healthKitStep: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "applewatch.watchface")
                .fixedFont(size: 56)
                .foregroundStyle(Theme.accent)
            Text("连接 Apple 健康")
                .font(.title2.bold())
            Text("授权后可自动同步体重、身高、年龄、性别与活动消耗，让热量预算更准确。")
                .font(.body)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)

            if healthKitRequested {
                Label("已请求授权，可在系统设置中调整", systemImage: "checkmark.circle.fill")
                    .font(.subheadline)
                    .foregroundStyle(.green)
            }

            Button {
                Task {
                    await healthContext?.healthKitService.requestAuthorization()
                    healthKitRequested = true
                    await applyHealthKitToGoalFields()
                    if let healthKit = healthContext?.healthKitService {
                        _ = await WorkoutPlanService.inferPreferencesFromHealthKitIfNeeded(
                            healthKit: healthKit,
                            modelContext: modelContext
                        )
                    }
                }
            } label: {
                Label("授权 HealthKit", systemImage: "heart.fill")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Theme.brandPrimary(colorScheme))
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadiusButton))
            }
            Spacer()
        }
        .padding(Theme.horizontalPadding)
    }

    private var aiStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("配置 AI 服务")
                .font(.title2.bold())
                .padding(.horizontal, Theme.horizontalPadding)
                .padding(.top, 8)

            Text("DeepSeek 用于文字录入与 AI 顾问，建议现在就配置。")
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
                .padding(.horizontal, Theme.horizontalPadding)

            AISettingsView(embeddedMode: true) {
                deepSeekConfigured = APIKeyManager.isDeepSeekConfigured
            }
        }
    }

    private var goalStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("设定减脂目标")
                    .font(.title2.bold())

                Text("优先使用 Apple 健康数据，缺失项请手动填写。")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)

                if !healthKitSyncedFields.isEmpty {
                    Label(
                        "已从 Apple 健康同步：\(healthKitSyncedFields.sorted().joined(separator: "、"))",
                        systemImage: "heart.text.square"
                    )
                    .font(.caption)
                    .foregroundStyle(.green)
                }

                Group {
                    weightField("当前体重", value: $currentWeight)
                    weightField("目标体重", value: $targetWeight)
                    weightField("身高 (cm)", value: $height, suffix: "cm")
                    stepperField("年龄", value: $age, range: 16...80)
                    Picker("性别", selection: $gender) {
                        Text("女").tag("female")
                        Text("男").tag("male")
                    }
                    DatePicker("目标日期", selection: $targetDate, in: Date()..., displayedComponents: .date)
                }
                .padding()
                .morandiCard()

                Text("本应用仅供参考，不能替代医疗诊断，请遵医嘱。")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            }
            .padding(Theme.horizontalPadding)
        }
        .task(id: step) {
            guard step == 3 else { return }
            await applyHealthKitToGoalFields()
        }
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        HStack {
            if step > 0 {
                Button("上一步") { step -= 1 }
                    .foregroundStyle(Theme.textSecondary)
            }

            Spacer()

            if step < totalSteps - 1 {
                Button("下一步") { advanceStep() }
                    .fontWeight(.semibold)
            } else {
                Button("开始使用", action: finishOnboarding)
                    .fontWeight(.semibold)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(Theme.brandPrimary(colorScheme))
                    .foregroundStyle(.white)
                    .clipShape(Capsule())
            }
        }
    }

    // MARK: - Helpers

    private func weightField(_ title: String, value: Binding<Double>, suffix: String = "kg") -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField(suffix, value: value, format: .number)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 72)
            Text(suffix)
                .foregroundStyle(Theme.textSecondary)
        }
    }

    private func stepperField(_ title: String, value: Binding<Int>, range: ClosedRange<Int>) -> some View {
        Stepper("\(title) \(value.wrappedValue) 岁", value: value, in: range)
    }

    private func advanceStep() {
        if step == 2 {
            deepSeekConfigured = APIKeyManager.isDeepSeekConfigured
        }
        step += 1
    }

    private func applyHealthKitToGoalFields() async {
        guard healthContext?.healthKitService.isHealthKitAvailable == true else { return }

        await healthContext?.healthKitService.fetchBodyProfile()
        guard let profile = healthContext?.healthKitService.bodyProfile else { return }

        var synced: [String] = []

        if let weightKg = profile.currentWeightKg {
            currentWeight = (weightKg * 10).rounded() / 10
            synced.append("当前体重")
        }

        if let heightCm = profile.heightCm, heightCm > 50, heightCm < 250 {
            height = (heightCm * 10).rounded() / 10
            synced.append("身高")
        }

        if let profileAge = profile.age, (16...100).contains(profileAge) {
            age = profileAge
            synced.append("年龄")
        }

        if let profileGender = profile.gender {
            gender = profileGender
            synced.append("性别")
        }

        if profile.currentWeightKg != nil {
            if gender == "male" {
                targetWeight = max(currentWeight - 3, 40)
                synced.append("目标体重建议")
            } else {
                targetWeight = UserGoal.femaleDefaultTargetWeightKg
            }
        } else if gender == "female" {
            targetWeight = UserGoal.femaleDefaultTargetWeightKg
        }

        healthKitSyncedFields = Set(synced)
    }

    private func finishOnboarding() {
        saveGoal()
        onComplete()
    }

    private func saveGoal() {
        let goal = UserGoal(
            targetWeight: targetWeight,
            height: height,
            age: age,
            gender: gender,
            activityLevel: "moderate",
            targetDate: targetDate
        )
        modelContext.insert(goal)

        let weightEntry = WeightEntry(weight: currentWeight)
        modelContext.insert(weightEntry)

        try? modelContext.save()
    }
}

#Preview {
    OnboardingView(onComplete: {})
        .healthContext(UnifiedHealthContext())
        .modelContainer(for: [UserGoal.self, WeightEntry.self], inMemory: true)
}
