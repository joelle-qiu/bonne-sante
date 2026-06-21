import SwiftUI
import SwiftData

/// 我的 / 设置 Tab
/// @author jiali.qiu
struct SettingsTabView: View {
    @Environment(\.healthContext) private var context
    @Environment(\.colorScheme) private var colorScheme

    @Query private var cycleProfiles: [CycleProfile]

    @State private var lastPeriodStart = Date()
    @State private var cycleLength = 28
    @State private var periodLength = 5
    @State private var syncFeedback: String?

    var body: some View {
        NavigationStack {
            List {
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
                    LabeledContent("版本", value: "阶段三开发中")
                    Text("本应用仅供参考，不能替代医疗诊断，请遵医嘱。")
                        .font(.caption)
                        .foregroundStyle(Theme.adaptiveTextSecondary(colorScheme))
                }
            }
            .navigationTitle("我的")
            .onAppear { loadCycleProfile() }
        }
    }

    @Environment(\.modelContext) private var modelContext

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
        .modelContainer(for: [CycleProfile.self], inMemory: true)
        .healthContext(UnifiedHealthContext())
}
