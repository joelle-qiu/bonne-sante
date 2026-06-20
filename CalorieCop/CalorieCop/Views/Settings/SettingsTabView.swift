import SwiftUI

import SwiftData



/// 我的 / 设置 Tab

/// @author jiali.qiu

struct SettingsTabView: View {

    @Environment(\.healthContext) private var context

    @Query private var cycleProfiles: [CycleProfile]



    @State private var lastPeriodStart = Date()

    @State private var cycleLength = 28



    var body: some View {

        NavigationStack {

            List {

                Section("AI 服务") {

                    HStack {

                        Text("状态")

                        Spacer()

                        Text(context?.aiStatus.summaryLabel ?? "未知")

                            .foregroundStyle(Theme.textSecondary)

                    }

                    NavigationLink("AI 服务配置") {

                        AISettingsView()

                            .navigationTitle("AI 服务配置")

                            .navigationBarTitleDisplayMode(.inline)

                    }

                }



                Section("生理周期") {

                    DatePicker("末次月经", selection: $lastPeriodStart, displayedComponents: .date)

                    Stepper("周期 \(cycleLength) 天", value: $cycleLength, in: 21...40)

                    Button("保存周期设置") {

                        saveCycleProfile()

                    }

                }



                Section("关于") {

                    LabeledContent("应用", value: "Bonne-Santé")

                    LabeledContent("版本", value: "阶段一开发中")

                    Text("本应用仅供参考，不能替代医疗诊断，请遵医嘱。")

                        .font(.caption)

                        .foregroundStyle(Theme.textSecondary)

                }

            }

            .navigationTitle("我的")

            .onAppear { loadCycleProfile() }

        }

    }



    @Environment(\.modelContext) private var modelContext



    private func loadCycleProfile() {

        if let profile = cycleProfiles.first {

            lastPeriodStart = profile.lastPeriodStart

            cycleLength = profile.averageCycleLength

        }

    }



    private func saveCycleProfile() {

        if let existing = cycleProfiles.first {

            existing.lastPeriodStart = lastPeriodStart

            existing.averageCycleLength = cycleLength

        } else {

            let profile = CycleProfile(lastPeriodStart: lastPeriodStart, averageCycleLength: cycleLength)

            modelContext.insert(profile)

        }

        try? modelContext.save()

    }

}



#Preview {

    SettingsTabView()

        .modelContainer(for: [CycleProfile.self], inMemory: true)

        .healthContext(UnifiedHealthContext())

}

