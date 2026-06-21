import SwiftUI
import SwiftData

/// 复查提醒：频率、下次日期、本地通知
/// @author jiali.qiu
struct CheckupPlansView: View {
    @Query(sort: \CheckupPlan.nextDueDate) private var plans: [CheckupPlan]

    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme

    @State private var feedback: String?
    @State private var planPendingDelete: CheckupPlan?

    var body: some View {
        Group {
            if plans.isEmpty {
                emptyState
            } else {
                planList
            }
        }
        .background(Theme.pageBackground(colorScheme).ignoresSafeArea())
        .navigationTitle("复查提醒")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await TodoService.requestAuthorization()
        }
        .alert("删除复查提醒？", isPresented: Binding(
            get: { planPendingDelete != nil },
            set: { if !$0 { planPendingDelete = nil } }
        ), presenting: planPendingDelete) { plan in
            Button("删除", role: .destructive) {
                deletePlan(plan)
            }
            Button("取消", role: .cancel) {
                planPendingDelete = nil
            }
        } message: { plan in
            Text("将移除「\(plan.metricName)」的复查提醒及本地通知。")
        }
        .overlay(alignment: .bottom) {
            if let feedback {
                Text(feedback)
                    .font(.caption)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial)
                    .clipShape(Capsule())
                    .padding(.bottom, 12)
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            self.feedback = nil
                        }
                    }
            }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("暂无复查提醒", systemImage: "calendar.badge.clock")
        } description: {
            Text("在「健康摘要 → 风险提醒」中点「设置复查提醒」，或在导入摘要里为主检建议设置随访周期。")
        } actions: {
            NavigationLink {
                HealthSummaryView()
            } label: {
                Text("前往健康摘要")
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.primaryDark)
        }
    }

    private var planList: some View {
        List {
            Section {
                Text("到期前 30 天、7 天本地通知。复查后可点「已完成」更新下次日期。")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            }

            Section("共 \(plans.count) 项") {
                ForEach(plans, id: \.id) { plan in
                    planRow(plan)
                }
            }

            Section {
                Text(RiskFlag.medicalDisclaimer)
                    .font(.caption2)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .listStyle(.insetGrouped)
    }

    private func planRow(_ plan: CheckupPlan) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(plan.metricName)
                        .font(.headline)
                    if !plan.department.isEmpty {
                        Text(plan.department)
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
                Spacer()
                dueBadge(plan)
            }

            HStack(spacing: 12) {
                Text("每 \(plan.frequencyInMonths) 个月")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                Text("下次 \(ReportDisplayFormatter.examDateLabel(plan.nextDueDate))")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(isOverdue(plan) ? Theme.adaptiveWarning(colorScheme) : Theme.adaptiveTextPrimary(colorScheme))
            }

            HStack(spacing: 12) {
                Menu {
                    ForEach([1, 3, 6, 12], id: \.self) { months in
                        Button("\(months) 个月") {
                            updateFrequency(plan, months: months)
                        }
                    }
                } label: {
                    Text("改周期")
                        .font(.caption.bold())
                }

                Button {
                    markCompletedToday(plan)
                } label: {
                    Text("已完成")
                        .font(.caption.bold())
                }

                Spacer()

                Button(role: .destructive) {
                    planPendingDelete = plan
                } label: {
                    Image(systemName: "trash")
                        .font(.caption)
                }
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func dueBadge(_ plan: CheckupPlan) -> some View {
        let days = daysUntil(plan.nextDueDate)
        if days < 0 {
            Text("已逾期")
                .font(.caption2.bold())
                .foregroundStyle(Theme.warning)
        } else if days <= 30 {
            Text("\(days) 天后")
                .font(.caption2.bold())
                .foregroundStyle(Theme.primaryDark)
        }
    }

    private func daysUntil(_ date: Date) -> Int {
        Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: Date()), to: Calendar.current.startOfDay(for: date)).day ?? 0
    }

    private func isOverdue(_ plan: CheckupPlan) -> Bool {
        plan.nextDueDate < Calendar.current.startOfDay(for: Date())
    }

    private func updateFrequency(_ plan: CheckupPlan, months: Int) {
        do {
            try HealthArchiveService.updateCheckupPlan(plan, frequencyMonths: months, modelContext: modelContext)
            feedback = "已设为 \(months) 个月"
        } catch {
            feedback = error.localizedDescription
        }
    }

    private func markCompletedToday(_ plan: CheckupPlan) {
        do {
            try HealthArchiveService.updateCheckupPlan(
                plan,
                frequencyMonths: plan.frequencyInMonths,
                lastExamDate: Date(),
                modelContext: modelContext
            )
            feedback = "已更新下次复查"
        } catch {
            feedback = error.localizedDescription
        }
    }

    private func deletePlan(_ plan: CheckupPlan) {
        do {
            try HealthArchiveService.deleteCheckupPlan(plan, modelContext: modelContext)
            planPendingDelete = nil
            feedback = "已删除"
        } catch {
            feedback = error.localizedDescription
        }
    }
}

#Preview {
    NavigationStack {
        CheckupPlansView()
    }
    .modelContainer(for: [CheckupPlan.self, Report.self], inMemory: true)
}
