import SwiftUI

/// 异常指标摘要：按优先级分色块展示
/// @author jiali.qiu
enum AbnormalSummaryBlocks {

    struct Style {
        let background: Color
        let border: Color
        let titleColor: Color
        let iconName: String
        let iconColor: Color
        let deptBackground: Color
        let itemIconColor: Color

        static func forPriority(_ priority: HealthProfileEngine.FollowUpPriority, scheme: ColorScheme) -> Style {
            let isDark = scheme == .dark
            switch priority {
            case .recheckOrTreat:
                return Style(
                    background: Theme.adaptiveWarning(scheme).opacity(isDark ? 0.22 : 0.14),
                    border: Theme.adaptiveWarning(scheme).opacity(isDark ? 0.55 : 0.38),
                    titleColor: isDark ? Color(hex: 0xFFB4B4) : Color(hex: 0xB85C5C),
                    iconName: "exclamationmark.triangle.fill",
                    iconColor: Theme.adaptiveWarning(scheme),
                    deptBackground: isDark ? Color.white.opacity(0.12) : Color.white.opacity(0.55),
                    itemIconColor: Theme.adaptiveWarning(scheme)
                )
            case .routineFollowUp:
                return Style(
                    background: Theme.brandPrimary(scheme).opacity(isDark ? 0.22 : 0.14),
                    border: Theme.link(scheme).opacity(isDark ? 0.45 : 0.32),
                    titleColor: Theme.link(scheme),
                    iconName: "calendar.badge.clock",
                    iconColor: Theme.link(scheme),
                    deptBackground: isDark ? Color.white.opacity(0.12) : Color.white.opacity(0.55),
                    itemIconColor: Theme.link(scheme)
                )
            }
        }
    }

    /// 导入摘要 / 健康摘要共用
    struct SectionView: View {
        let title: String
        let groups: [HealthProfileEngine.AbnormalPriorityGroup]
        var compact: Bool = false
        @Environment(\.colorScheme) private var colorScheme

        var body: some View {
            VStack(alignment: .leading, spacing: 12) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(Theme.adaptiveTextPrimary(colorScheme))
                ForEach(groups) { group in
                    PriorityBlockView(group: group, compact: compact)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    struct PriorityBlockView: View {
        let group: HealthProfileEngine.AbnormalPriorityGroup
        var compact: Bool = false
        @Environment(\.colorScheme) private var colorScheme

        private var style: Style { Style.forPriority(group.id, scheme: colorScheme) }
        private var itemCount: Int {
            group.departments.reduce(0) { $0 + $1.items.count }
        }

        var body: some View {
            VStack(alignment: .leading, spacing: compact ? 8 : 10) {
                HStack(spacing: 8) {
                    Image(systemName: style.iconName)
                        .font(.subheadline)
                        .foregroundStyle(style.iconColor)
                    Text(group.title)
                        .font(compact ? .caption.weight(.semibold) : .subheadline.weight(.semibold))
                        .foregroundStyle(style.titleColor)
                    Spacer(minLength: 0)
                    Text("\(itemCount) 项")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(style.titleColor.opacity(0.85))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(style.deptBackground)
                        .clipShape(Capsule())
                }

                ForEach(group.departments) { dept in
                    DepartmentBlockView(
                        department: dept,
                        style: style,
                        compact: compact
                    )
                }
            }
            .padding(compact ? 12 : 14)
            .background(style.background)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cornerRadiusCard)
                    .stroke(style.border, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadiusCard))
        }
    }

    private struct DepartmentBlockView: View {
        let department: HealthProfileEngine.AbnormalDepartmentGroup
        let style: Style
        var compact: Bool
        @Environment(\.colorScheme) private var colorScheme

        var body: some View {
            VStack(alignment: .leading, spacing: compact ? 4 : 6) {
                Text(department.department)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(style.titleColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(style.deptBackground)
                    .clipShape(Capsule())

                ForEach(department.items) { item in
                    if compact {
                        Label(item.compactLine, systemImage: "circle.fill")
                            .font(.caption)
                            .foregroundStyle(Theme.adaptiveTextPrimary(colorScheme))
                            .labelStyle(.titleAndIcon)
                            .symbolRenderingMode(.monochrome)
                            .tint(style.itemIconColor)
                    } else {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "circle.fill")
                                .fixedFont(size: 6)
                                .foregroundStyle(style.itemIconColor)
                                .padding(.top, 6)
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 4) {
                                    Text("\(item.name) \(item.valueSummary)")
                                        .font(.subheadline)
                                        .foregroundStyle(Theme.adaptiveTextPrimary(colorScheme))
                                    if let arrow = item.trendArrow {
                                        Text(arrow)
                                            .font(.subheadline.weight(.bold))
                                            .foregroundStyle(arrow == "↑" ? Theme.adaptiveWarning(colorScheme) : Theme.brandPrimary(colorScheme))
                                    }
                                }
                                if !item.actionHint.isEmpty {
                                    Text(item.actionHint)
                                        .font(.caption)
                                        .foregroundStyle(Theme.adaptiveTextSecondary(colorScheme))
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
