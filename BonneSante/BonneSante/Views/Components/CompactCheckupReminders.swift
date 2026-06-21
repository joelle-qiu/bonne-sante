import SwiftUI

/// 首页底部紧凑复查待办（已生成的 CheckupPlan）
/// @author jiali.qiu
struct CompactCheckupReminders: View {
    let plans: [CheckupPlan]
    var maxVisible: Int = 2

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        if plans.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("复查待办")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.adaptiveTextPrimary(colorScheme))
                    Spacer()
                    NavigationLink {
                        CheckupPlansView()
                    } label: {
                        Text(plans.count > maxVisible ? "全部 \(plans.count) 项" : "管理")
                            .font(.caption)
                    }
                    .foregroundStyle(Theme.link(colorScheme))
                }

                VStack(spacing: 0) {
                    ForEach(Array(plans.prefix(maxVisible).enumerated()), id: \.element.id) { index, plan in
                        reminderRow(plan)
                        if index < min(plans.count, maxVisible) - 1 {
                            Divider().padding(.leading, 36)
                        }
                    }
                }
                .padding(.vertical, 4)
                .morandiCard()

                Text(RiskFlag.medicalDisclaimer)
                    .font(.caption2)
                    .foregroundStyle(Theme.adaptiveTextSecondary(colorScheme))
            }
        }
    }

    private func reminderRow(_ plan: CheckupPlan) -> some View {
        HStack(spacing: 12) {
            Image(systemName: statusIcon(for: plan))
                .font(.body)
                .foregroundStyle(statusColor(for: plan))
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(plan.metricName)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.adaptiveTextPrimary(colorScheme))
                    .lineLimit(1)
                Text(dueLabel(for: plan))
                    .font(.caption)
                    .foregroundStyle(Theme.adaptiveTextSecondary(colorScheme))
            }

            Spacer(minLength: 0)

            if isOverdue(plan) {
                Text("待复查")
                    .font(.caption2.weight(.bold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Theme.adaptiveWarning(colorScheme).opacity(0.2))
                    .foregroundStyle(Theme.adaptiveWarning(colorScheme))
                    .clipShape(Capsule())
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 4)
    }

    private func dueLabel(for plan: CheckupPlan) -> String {
        let date = plan.nextDueDate.formatted(date: .abbreviated, time: .omitted)
        let days = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: Date()), to: Calendar.current.startOfDay(for: plan.nextDueDate)).day ?? 0
        if days < 0 { return "\(date) · 已逾期 \(abs(days)) 天" }
        if days == 0 { return "\(date) · 今天到期" }
        if days <= 30 { return "\(date) · 还有 \(days) 天" }
        return "\(date) · 每 \(plan.frequencyInMonths) 个月"
    }

    private func isOverdue(_ plan: CheckupPlan) -> Bool {
        plan.nextDueDate < Calendar.current.startOfDay(for: Date())
    }

    private func statusIcon(for plan: CheckupPlan) -> String {
        isOverdue(plan) ? "exclamationmark.circle.fill" : "calendar.badge.clock"
    }

    private func statusColor(for plan: CheckupPlan) -> Color {
        isOverdue(plan) ? Theme.adaptiveWarning(colorScheme) : Theme.brandPrimary(colorScheme)
    }
}

#Preview {
    CompactCheckupReminders(plans: [])
        .padding()
}
