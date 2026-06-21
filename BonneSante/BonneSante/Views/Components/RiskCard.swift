import SwiftUI

/// 风险卡片（含医疗免责声明）
/// @author jiali.qiu
struct RiskCard: View {
    let title: String
    let value: String
    let trend: String
    let action: String
    let severity: RiskSeverity
    var suggestedCheckupMonths: Int = 3
    var department: String = ""
    var onScheduleCheckup: ((Int) -> Void)?

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: iconName)
                    .foregroundStyle(severityColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(Theme.adaptiveTextPrimary(colorScheme))
                    if !department.isEmpty {
                        Text(department)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(Theme.departmentLabel(colorScheme))
                    }
                }
                Spacer()
                Text(severityLabel)
                    .font(.caption2.bold())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(severityColor.opacity(colorScheme == .dark ? 0.28 : 0.2))
                    .foregroundStyle(severityColor)
                    .clipShape(Capsule())
            }

            Text("当前：\(value)")
                .font(.subheadline)
                .foregroundStyle(Theme.adaptiveTextPrimary(colorScheme))
            if !trend.isEmpty, trend != MetricTrend.unknown.rawValue {
                Text("趋势：\(trend)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(trendColor)
            }
            Text(action)
                .font(.subheadline)
                .foregroundStyle(Theme.adaptiveTextPrimary(colorScheme))

            Text(RiskFlag.medicalDisclaimer)
                .font(.caption2)
                .foregroundStyle(Theme.adaptiveTextSecondary(colorScheme))

            HStack(spacing: 10) {
                if let onScheduleCheckup {
                    Menu {
                        ForEach([1, 3, 6, 12], id: \.self) { months in
                            Button("\(months) 个月后复查") {
                                onScheduleCheckup(months)
                            }
                        }
                    } label: {
                        Label("设置复查提醒", systemImage: "calendar.badge.clock")
                            .font(.subheadline.bold())
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(Theme.primary.opacity(0.35))
                            .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadiusButton))
                    }
                }
            }
        }
        .morandiCard()
    }

    private var severityColor: Color {
        switch severity {
        case .high: return Theme.adaptiveWarning(colorScheme)
        case .medium: return Theme.adaptiveAccent(colorScheme)
        case .low: return Theme.brandPrimary(colorScheme)
        }
    }

    private var trendColor: Color {
        if trend.contains("恶化") { return Theme.adaptiveWarning(colorScheme) }
        if trend.contains("改善") { return Theme.brandPrimary(colorScheme) }
        return Theme.adaptiveTextSecondary(colorScheme)
    }

    private var severityLabel: String {
        switch severity {
        case .high: return "优先"
        case .medium: return "关注"
        case .low: return "提示"
        }
    }

    private var iconName: String {
        switch severity {
        case .high: return "exclamationmark.triangle.fill"
        case .medium: return "bell.badge.fill"
        case .low: return "info.circle.fill"
        }
    }
}

#Preview {
    RiskCard(
        title: "肺结节",
        value: "5mm",
        trend: "→ 持平",
        action: "建议年度胸部 CT 复查",
        severity: .high,
        onScheduleCheckup: { _ in }
    )
    .padding()
}
