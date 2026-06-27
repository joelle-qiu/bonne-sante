import SwiftUI
import SwiftData

/// 我的 / 设置 Tab
/// @author jiali.qiu
struct SettingsTabView: View {
    @Environment(\.healthContext) private var context
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.modelContext) private var modelContext

    @Query private var cycleProfiles: [CycleProfile]
    @Query private var settingsList: [UserSettings]

    @State private var lastPeriodStart = Date()
    @State private var cycleLength = 28
    @State private var periodLength = 5
    @State private var syncFeedback: String?

    private var userSettings: UserSettings {
        if let existing = settingsList.first { return existing }
        let created = UserSettings()
        modelContext.insert(created)
        try? modelContext.save()
        return created
    }

    var body: some View {
        NavigationStack {
            List {
                appearanceSection
                profileSection
                workoutReminderSection

                Section("AI 服务") {
                    HStack {
                        Text("状态")
                        Spacer()
                        Text(context?.aiStatus.summaryLabel ?? "未知")
                            .foregroundStyle(Theme.adaptiveTextSecondary(colorScheme))
                    }
                    NavigationLink("AI 服务配置") {
                        AISettingsView()
                            .navigationTitle("AI 服务配置")
                            .navigationBarTitleDisplayMode(.inline)
                    }
                }

                Section("Apple 健康同步") {
                    LabeledContent("数据状态", value: healthKitStatusLabel)
                    bodyCompositionDebugRows
                    if let intel = context?.intelligenceProfile {
                        LabeledContent("基础代谢 BMR", value: "\(Int(intel.bmrKcal)) 大卡")
                        LabeledContent("BMR 来源", value: intel.bmrSourceShort)
                        LabeledContent("日均总消耗 TDEE", value: "\(Int(intel.tdeeKcal)) 大卡")
                        LabeledContent("TDEE 来源", value: intel.tdeeSourceShort)
                        if intel.basalWatchSampleDays >= 3 {
                            LabeledContent("BMR 采样", value: "近7日 \(intel.basalWatchSampleDays) 天")
                        }
                        if let katch = intel.katchBmrKcal {
                            LabeledContent("体成分对照 BMR", value: "\(Int(katch)) 大卡")
                        }
                        if let lean = intel.leanBodyMassKg {
                            LabeledContent("去脂体重", value: String(format: "%.1f kg", lean))
                        }
                    }
                    LabeledContent("今日活动消耗", value: "\(Int(context?.healthKitService.activeCaloriesBurned ?? 0)) 大卡")
                    LabeledContent("今日基础代谢", value: "\(Int(context?.healthKitService.basalCaloriesBurned ?? 0)) 大卡")
                    if let weight = context?.healthKitService.currentWeight {
                        LabeledContent("最近体重", value: String(format: "%.1f kg", weight))
                    } else {
                        LabeledContent("最近体重", value: "暂无")
                    }
                    menstrualHealthRows
                    if let refreshed = context?.lastRefreshedAt {
                        LabeledContent("最近同步", value: refreshed.formatted(date: .omitted, time: .shortened))
                    }
                    Button("重新请求授权") {
                        Task { await context?.healthKitService.requestAuthorization() }
                    }
                    Button("刷新体成分") {
                        Task {
                            await context?.healthKitService.fetchBodyProfile()
                            syncFeedback = "已刷新体成分"
                        }
                    }
                }

                Section("生理周期") {
                    if let info = context?.cyclePhaseInfo, info.phase != .unknown {
                        LabeledContent("当前阶段", value: info.label)
                        if let days = info.daysUntilNextPeriod {
                            LabeledContent("预计下次来潮", value: days == 0 ? "今天" : "\(days) 天后")
                        }
                    }

                    DatePicker("末次月经", selection: $lastPeriodStart, displayedComponents: .date)
                    Stepper("周期 \(cycleLength) 天", value: $cycleLength, in: 21...45)
                    Stepper("经期 \(periodLength) 天", value: $periodLength, in: 2...10)

                    Button("保存手动设置") {
                        saveCycleProfile(source: .manual)
                    }

                    Button("从 Apple 健康同步经期") {
                        Task { await syncFromHealthKit() }
                    }

                    if let syncFeedback {
                        Text(syncFeedback)
                            .font(.caption)
                            .foregroundStyle(Theme.adaptiveTextSecondary(colorScheme))
                    }
                }

                Section("关于") {
                    LabeledContent("应用", value: "Bonne-Santé")
                    LabeledContent("版本", value: "MVP · 阶段三")
                    Text("本应用仅供参考，不能替代医疗诊断，请遵医嘱。")
                        .font(.caption)
                        .foregroundStyle(Theme.adaptiveTextSecondary(colorScheme))
                }
            }
            .scrollContentBackground(.hidden)
            .cycleThemedPageBackground()
            .navigationTitle("我的")
            .onAppear {
                loadCycleProfile()
                if settingsList.isEmpty {
                    modelContext.insert(UserSettings())
                    try? modelContext.save()
                }
                WorkoutMorningReminderService.sync(modelContext: modelContext)
            }
        }
    }

    private var appearanceSection: some View {
        Section {
            Picker("外观模式", selection: appearanceBinding) {
                ForEach(AppAppearanceMode.allCases) { mode in
                    Label(mode.label, systemImage: mode.icon)
                        .tag(mode)
                }
            }
            .pickerStyle(.inline)

            HStack {
                Text("当前生效")
                Spacer()
                Text(activeAppearanceLabel)
                    .foregroundStyle(Theme.adaptiveTextSecondary(colorScheme))
            }
        } header: {
            Text("显示与主题")
        } footer: {
            Text("可选择日间或夜间固定模式，也可跟随系统。后续将支持更多背景与周期主题效果。")
                .font(.caption)
                .foregroundStyle(Theme.adaptiveTextTertiary(colorScheme))
        }
    }

    private var profileSection: some View {
        Section {
            TextField("称呼（选填）", text: nicknameBinding)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        } header: {
            Text("个人")
        } footer: {
            if userSettings.prefersMoodWorkoutProfile {
                Text("已识别为心情健身用户。训练计划 → 切换「心情」模式，下雨推荐游泳、晴天推荐跳舞。")
                    .font(.caption)
                    .foregroundStyle(Theme.adaptiveTextTertiary(colorScheme))
            } else {
                Text("填写「小姜」等称呼后，训练计划页会推荐心情模式。")
                    .font(.caption)
                    .foregroundStyle(Theme.adaptiveTextTertiary(colorScheme))
            }
        }
    }

    private var workoutReminderSection: some View {
        Section {
            Toggle("训练日晨间提醒", isOn: workoutReminderEnabledBinding)
            if userSettings.workoutMorningReminderEnabled {
                DatePicker(
                    "提醒时间",
                    selection: workoutReminderTimeBinding,
                    displayedComponents: .hourAndMinute
                )
            }
        } header: {
            Text("训练提醒")
        } footer: {
            Text("仅在「今天有排课」的当天推送一条提醒，不会提前把整周计划都排进通知。重新打开 App 或生成计划后会自动刷新。")
                .font(.caption)
                .foregroundStyle(Theme.adaptiveTextTertiary(colorScheme))
        }
    }

    private var workoutReminderEnabledBinding: Binding<Bool> {
        Binding(
            get: { userSettings.workoutMorningReminderEnabled },
            set: { newValue in
                userSettings.workoutMorningReminderEnabled = newValue
                try? modelContext.save()
                WorkoutMorningReminderService.sync(modelContext: modelContext)
            }
        )
    }

    private var workoutReminderTimeBinding: Binding<Date> {
        Binding(
            get: { userSettings.workoutMorningReminderTime },
            set: { newValue in
                userSettings.workoutMorningReminderTime = newValue
                try? modelContext.save()
                WorkoutMorningReminderService.sync(modelContext: modelContext)
            }
        )
    }

    private var nicknameBinding: Binding<String> {
        Binding(
            get: { userSettings.profileNickname },
            set: { newValue in
                userSettings.profileNickname = newValue
                try? modelContext.save()
            }
        )
    }

    private var appearanceBinding: Binding<AppAppearanceMode> {
        Binding(
            get: { userSettings.preferredAppearance },
            set: { newValue in
                userSettings.preferredAppearance = newValue
                try? modelContext.save()
            }
        )
    }

    private var activeAppearanceLabel: String {
        switch userSettings.preferredAppearance {
        case .system:
            return colorScheme == .dark ? "跟随系统 · 夜间" : "跟随系统 · 日间"
        case .light:
            return "日间模式"
        case .dark:
            return "夜间模式"
        }
    }

    @ViewBuilder
    private var bodyCompositionDebugRows: some View {
        let profile = context?.healthKitService.bodyProfile ?? .empty
        if let bf = profile.bodyFatPercent {
            LabeledContent("体脂率（校正后）", value: String(format: "%.1f%%", bf))
        }
        if let raw = profile.bodyFatRawHealthKit {
            LabeledContent("体脂原始值", value: String(format: "%.4f", raw))
        }
        if let source = profile.bodyFatSourceName {
            LabeledContent("体成分来源", value: source)
        }
        if let measured = profile.bodyFatMeasuredAt {
            LabeledContent("体成分时间", value: measured.formatted(date: .abbreviated, time: .shortened))
        }
        if let compWeight = profile.compositionWeightKg {
            LabeledContent("同次测量体重", value: String(format: "%.1f kg", compWeight))
        }
    }

    @ViewBuilder
    private var menstrualHealthRows: some View {
        let snapshot = context?.healthKitService.menstrualSnapshot ?? .empty
        LabeledContent("经期记录", value: snapshot.loggedFlowDays > 0 ? "\(snapshot.loggedFlowDays) 天" : "暂无")
        if let start = snapshot.lastPeriodStart {
            LabeledContent("健康末次月经", value: start.formatted(date: .abbreviated, time: .omitted))
        }
        if let cycle = snapshot.inferredCycleLength {
            LabeledContent("推断周期", value: "\(cycle) 天")
        }
        Text("读取：活动消耗、基础代谢、体重、经期流量。需在「健康」App 中开启经期跟踪。")
            .font(.caption)
            .foregroundStyle(Theme.adaptiveTextSecondary(colorScheme))
    }

    private var healthKitStatusLabel: String {
        guard let service = context?.healthKitService else { return "未知" }
        if !service.isHealthKitAvailable { return "设备不支持" }
        if service.totalCaloriesBurned > 0 || service.currentWeight != nil || service.menstrualSnapshot.lastPeriodStart != nil {
            return "已同步"
        }
        if service.authorizationError != nil { return "授权异常" }
        if service.isAuthorized { return "已授权，暂无数据" }
        return "未授权"
    }

    private func loadCycleProfile() {
        if let profile = cycleProfiles.first {
            lastPeriodStart = profile.lastPeriodStart
            cycleLength = profile.averageCycleLength
            periodLength = profile.averagePeriodLength
        }
    }

    private func saveCycleProfile(source: CycleEngine.DataSource) {
        if let existing = cycleProfiles.first {
            existing.lastPeriodStart = lastPeriodStart
            existing.averageCycleLength = cycleLength
            existing.averagePeriodLength = periodLength
            existing.dataSource = source.rawValue
            if source == .manual {
                existing.lastSyncedAt = nil
            }
        } else {
            let profile = CycleProfile(
                lastPeriodStart: lastPeriodStart,
                averageCycleLength: cycleLength,
                averagePeriodLength: periodLength,
                dataSource: source.rawValue
            )
            modelContext.insert(profile)
        }
        try? modelContext.save()
        syncFeedback = "已保存手动周期设置"
    }

    private func syncFromHealthKit() async {
        await context?.healthKitService.fetchMenstrualCycleSnapshot()
        guard let snapshot = context?.healthKitService.menstrualSnapshot,
              let start = snapshot.lastPeriodStart else {
            syncFeedback = "未在 Apple 健康中找到经期记录，请先在「健康」App 中记录。"
            return
        }

        if let existing = cycleProfiles.first {
            guard CycleEngine.applyHealthKitSnapshot(snapshot, to: existing) else {
                syncFeedback = "同步失败，请稍后重试。"
                return
            }
        } else {
            let profile = CycleProfile(
                lastPeriodStart: start,
                averageCycleLength: snapshot.inferredCycleLength ?? 28,
                averagePeriodLength: snapshot.inferredPeriodLength ?? 5,
                dataSource: CycleEngine.DataSource.healthKit.rawValue,
                lastSyncedAt: Date()
            )
            modelContext.insert(profile)
        }

        try? modelContext.save()
        loadCycleProfile()
        syncFeedback = "已从 Apple 健康同步末次月经：\(start.formatted(date: .abbreviated, time: .omitted))"
    }
}

#Preview {
    SettingsTabView()
        .modelContainer(for: [CycleProfile.self, UserSettings.self], inMemory: true)
        .healthContext(UnifiedHealthContext())
}
