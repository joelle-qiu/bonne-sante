import SwiftUI
import SwiftData
import Charts

/// 跨报告健康趋势（化验指标 + 检查结论）
/// @author jiali.qiu
struct HealthMetricTrendView: View {
    @Query(filter: #Predicate<Report> { $0.isVerified }, sort: \Report.examDate, order: .forward)
    private var reports: [Report]

    @Environment(\.colorScheme) private var colorScheme

    var focusPanelId: String?
    var focusLineId: String?

    private var metricPanels: [HealthMetricTrendEngine.TrendPanel] {
        HealthMetricTrendEngine.buildPanels(from: reports)
    }

    private var findingPanels: [HealthMetricTrendEngine.TrendPanel] {
        HealthFindingTrendEngine.buildPanels(from: reports)
    }

    private var hasAnyTrendData: Bool {
        HealthMetricTrendEngine.verifiedReportCount(from: reports) >= 2
    }

    private var overview: HealthMetricTrendEngine.TrendOverview {
        let metric = HealthMetricTrendEngine.buildOverview(from: reports)
        let finding = HealthFindingTrendEngine.buildOverview(from: reports)
        return HealthMetricTrendEngine.TrendOverview(
            recovered: metric.recovered + finding.recovered,
            newConcern: metric.newConcern + finding.newConcern,
            ongoing: metric.ongoing + finding.ongoing,
            improving: metric.improving + finding.improving,
            stableGood: metric.stableGood + finding.stableGood,
            singleRecord: metric.singleRecord + finding.singleRecord
        )
    }

    @State private var expandedStablePanels: Set<String> = []
    @State private var expandedSingleRecordPanels: Set<String> = []

    private let lineColors: [Color] = [
        Theme.primaryDark,
        Theme.accent,
        Theme.warning,
        Color.blue,
        Color.purple
    ]

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if !hasAnyTrendData {
                        emptyState
                    } else {
                        overviewCard
                        legendHint

                        if !metricPanels.isEmpty {
                            sectionHeader("化验指标", systemImage: "testtube.2")
                            trendPanelSection(panels: metricPanels)
                        }

                        if !findingPanels.isEmpty {
                            sectionHeader("检查结论", systemImage: "waveform.path.ecg.rectangle")
                            trendPanelSection(panels: findingPanels)
                        }
                    }
                    disclaimer
                }
                .padding(.horizontal, Theme.horizontalPadding)
                .padding(.vertical, 16)
            }
            .cycleThemedPageBackground()
            .navigationTitle("健康趋势")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                applyFocusFromDeepLink()
                scrollToFocusedLine(using: proxy)
            }
        }
    }

    /// 深链进入时展开含目标 line 的面板，并优先展示对应 panel
    private func applyFocusFromDeepLink() {
        if focusLineId == nil {
            expandImagingFollowUpPanels()
            return
        }
        guard let lineId = focusLineId else { return }
        for panel in metricPanels + findingPanels {
            guard panel.lines.contains(where: { $0.id == lineId }) else { continue }
            if panel.singleRecordLines.contains(where: { $0.id == lineId }) {
                expandedSingleRecordPanels.insert(panel.id)
            }
            if panel.stableLines.contains(where: { $0.id == lineId }) {
                expandedStablePanels.insert(panel.id)
            }
        }
    }

    private func scrollToFocusedLine(using proxy: ScrollViewProxy) {
        guard let lineId = focusLineId else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            withAnimation(.easeInOut(duration: 0.35)) {
                proxy.scrollTo(lineId, anchor: .top)
            }
        }
    }

    /// 肺结节 / 肝血管瘤等长期随访项默认展开，避免藏在折叠区
    private func expandImagingFollowUpPanels() {
        let followUpIds: Set<String> = ["imaging.lung_nodule", "imaging.liver_lesion"]
        for panel in findingPanels where panel.id == "finding.imaging" {
            let hasFollowUp = panel.lines.contains { followUpIds.contains($0.id) }
            if hasFollowUp {
                expandedSingleRecordPanels.insert(panel.id)
            }
        }
    }

    private func sectionHeader(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Theme.textPrimary)
            .padding(.top, 4)
    }

    @ViewBuilder
    private func trendPanelSection(panels: [HealthMetricTrendEngine.TrendPanel]) -> some View {
        let resolvedPanelId = focusPanelId ?? panelIdContainingFocusLine(in: panels)
        if let resolvedPanelId,
           let focused = panels.first(where: { $0.id == resolvedPanelId }) {
            panelCard(focused, emphasized: true, stableLabel: stableItemLabel(for: focused))
        }
        ForEach(panels.filter { $0.id != resolvedPanelId }) { panel in
            panelCard(panel, emphasized: false, stableLabel: stableItemLabel(for: panel))
        }
    }

    private func panelIdContainingFocusLine(in panels: [HealthMetricTrendEngine.TrendPanel]) -> String? {
        guard let lineId = focusLineId else { return nil }
        return panels.first(where: { $0.lines.contains(where: { $0.id == lineId }) })?.id
    }

    private func stableItemLabel(for panel: HealthMetricTrendEngine.TrendPanel) -> String {
        panel.id.hasPrefix("finding.") ? "结论" : "指标"
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "chart.xyaxis.line")
                .font(.system(size: 40))
                .foregroundStyle(Theme.textSecondary)
            Text("暂无可对比的趋势")
                .font(.headline)
            Text("导入至少 2 份已校对报告后，可在此查看化验指标与检查结论是变好了还是需关注。")
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .morandiCard()
    }

    private var overviewCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("变化一览")
                .font(.headline)
            HStack(spacing: 6) {
                overviewChip(count: overview.newConcern, label: "新出现", color: Theme.warning)
                overviewChip(count: overview.ongoing, label: "仍需关注", color: Theme.warning.opacity(0.85))
                overviewChip(count: overview.improving, label: "好转中", color: Theme.primaryDark)
                overviewChip(count: overview.recovered, label: "已好转", color: Theme.primaryDark)
            }
            HStack(spacing: 6) {
                overviewChip(count: overview.stableGood, label: "保持正常", color: Theme.textSecondary)
                overviewChip(count: overview.singleRecord, label: "待复查对比", color: Color.blue)
            }
            Text("「待复查对比」= 仅一家医院测过，下次体检需做同项才能看变化。异常项会排在前面。")
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
        }
        .morandiCard()
    }

    private func overviewChip(count: Int, label: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text("\(count)")
                .font(.title3.bold())
                .foregroundStyle(count > 0 ? color : Theme.textSecondary.opacity(0.5))
            Text(label)
                .font(.caption2)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(color.opacity(count > 0 ? 0.12 : 0.05))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var legendHint: some View {
        Text("可对比项看走向；单次记录默认收起，待下次同项检查后再比。")
            .font(.caption)
            .foregroundStyle(Theme.textSecondary)
    }

    private func panelCard(
        _ panel: HealthMetricTrendEngine.TrendPanel,
        emphasized: Bool,
        stableLabel: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            panelHeader(panel, emphasized: emphasized)

            if !panel.notableLines.isEmpty {
                VStack(spacing: 10) {
                    ForEach(panel.notableLines) { line in
                        statusRow(line, emphasized: line.id == focusLineId)
                    }
                }
                if panel.notableLines.contains(where: { !$0.unit.isEmpty || $0.rawPoints.contains(where: { $0.value > 1 }) }) {
                    notableChart(panel.notableLines, emphasized: emphasized)
                }
            } else if panel.hasComparableLines {
                allStableBanner(count: panel.stableLines.count, itemLabel: stableLabel)
            }

            if !panel.singleRecordLines.isEmpty {
                singleRecordDisclosure(panel, itemLabel: stableLabel)
            }

            if !panel.stableLines.isEmpty {
                stableDisclosure(panel, itemLabel: stableLabel)
            }
        }
        .morandiCard()
    }

    private func panelHeader(_ panel: HealthMetricTrendEngine.TrendPanel, emphasized: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(panel.title)
                .font(emphasized ? .title3.bold() : .headline)
            Text(panel.subtitle)
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
            HStack(spacing: 6) {
                ForEach(panel.relatedSystems, id: \.self) { system in
                    Text(system)
                        .font(.caption2)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Theme.primary.opacity(0.2))
                        .clipShape(Capsule())
                }
            }
        }
    }

    private func statusRow(_ line: HealthMetricTrendEngine.TrendLine, emphasized: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(line.plainTitle)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.adaptiveTextPrimary(colorScheme))
                    Text(line.metricType)
                        .font(.caption2)
                        .foregroundStyle(Theme.adaptiveTextSecondary(colorScheme))
                }
                Spacer()
                statusBadge(line.status)
            }
            Text(line.relatedTo)
                .font(.caption)
                .foregroundStyle(Theme.adaptiveTextSecondary(colorScheme))
            Text(line.statusNote)
                .font(.caption)
                .foregroundStyle(statusColor(line.status))
            if !line.assessmentNote.isEmpty {
                Text(line.assessmentNote)
                    .font(.caption2)
                    .foregroundStyle(Theme.adaptiveTextSecondary(colorScheme))
            }
            if line.status == .singleRecord, let point = line.rawPoints.first {
                HStack(spacing: 6) {
                    Image(systemName: "calendar")
                        .font(.caption2)
                    Text(ReportDisplayFormatter.examDateLabel(point.date))
                    Text("·")
                    Text(formattedTrendSize(line, preferFirst: false))
                        .foregroundStyle(point.isAbnormal ? Theme.adaptiveWarning(colorScheme) : Theme.adaptiveTextSecondary(colorScheme))
                }
                .font(.caption2)
                .foregroundStyle(Theme.adaptiveTextSecondary(colorScheme))
            } else {
                HStack(spacing: 12) {
                    Text("较早 \(formattedTrendSize(line, preferFirst: true))")
                    Image(systemName: "arrow.right")
                        .font(.caption2)
                        .foregroundStyle(Theme.adaptiveTextSecondary(colorScheme))
                    Text("最近 \(formattedTrendSize(line, preferFirst: false))")
                }
                .font(.caption2)
                .foregroundStyle(Theme.adaptiveTextSecondary(colorScheme))
            }
        }
        .padding(10)
        .background(statusColor(line.status).opacity(emphasized ? 0.16 : 0.08))
        .overlay {
            if emphasized {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Theme.adaptiveAccent(colorScheme), lineWidth: 2)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .id(line.id)
    }

    private func formattedTrendSize(_ line: HealthMetricTrendEngine.TrendLine, preferFirst: Bool) -> String {
        guard let point = preferFirst ? line.rawPoints.first : line.rawPoints.last else {
            let fallback = preferFirst ? line.firstValueText : line.latestValueText
            return sanitizedSizeLabel(fallback)
        }
        if let mm = point.sizeMillimeters, mm > 0 {
            return String(format: "%.1f mm", mm)
        }
        if point.value > 0 {
            return String(format: "%.1f mm", point.value)
        }
        let text = preferFirst ? line.firstValueText : line.latestValueText
        return sanitizedSizeLabel(text)
    }

    private func sanitizedSizeLabel(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "—" }
        let bareOrgans: Set<String> = ["肝脏", "肺部", "肺", "肝", "双乳", "子宫", "宫颈", "甲状腺"]
        if bareOrgans.contains(trimmed) { return "—" }
        return trimmed
    }

    private func statusBadge(_ status: MetricTrendCatalog.HealthStatus) -> some View {
        Text(status.rawValue)
            .font(.caption2.bold())
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(statusColor(status).opacity(0.2))
            .foregroundStyle(statusColor(status))
            .clipShape(Capsule())
    }

    private func statusColor(_ status: MetricTrendCatalog.HealthStatus) -> Color {
        switch status {
        case .recovered: return Theme.brandPrimary(colorScheme)
        case .improvingAbnormal: return Theme.brandPrimary(colorScheme)
        case .newConcern, .ongoing: return Theme.adaptiveWarning(colorScheme)
        case .stableGood: return Theme.adaptiveTextSecondary(colorScheme)
        case .singleRecord: return Theme.link(colorScheme)
        case .unclear: return Theme.adaptiveTextSecondary(colorScheme)
        }
    }

    private func allStableBanner(count: Int, itemLabel: String) -> some View {
        Label("本类 \(count) 项\(itemLabel)均保持正常", systemImage: "checkmark.circle.fill")
            .font(.subheadline)
            .foregroundStyle(Theme.primaryDark)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(Theme.primary.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    @ViewBuilder
    private func notableChart(_ lines: [HealthMetricTrendEngine.TrendLine], emphasized: Bool) -> some View {
        Chart {
            ForEach(lines) { line in
                ForEach(line.points) { point in
                    LineMark(
                        x: .value("日期", point.date),
                        y: .value("指数", point.index)
                    )
                    .foregroundStyle(by: .value("指标", line.plainTitle))
                    .interpolationMethod(.catmullRom)

                    PointMark(
                        x: .value("日期", point.date),
                        y: .value("指数", point.index)
                    )
                    .foregroundStyle(by: .value("指标", line.plainTitle))
                    .symbolSize(emphasized ? 40 : 28)
                }
            }
            RuleMark(y: .value("基准", 100))
                .foregroundStyle(Theme.textSecondary.opacity(0.3))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
        }
        .chartForegroundStyleScale(range: lineColors)
        .chartYAxisLabel("相对趋势")
        .chartXAxis {
            AxisMarks(values: .automatic) { _ in
                AxisGridLine()
                AxisValueLabel(format: .dateTime.year().month(.narrow))
            }
        }
        .frame(height: emphasized ? 180 : 150)
    }

    private func singleRecordDisclosure(_ panel: HealthMetricTrendEngine.TrendPanel, itemLabel: String) -> some View {
        let abnormalCount = panel.singleRecordLines.filter { $0.rawPoints.first?.isAbnormal == true }.count
        return DisclosureGroup(
            isExpanded: Binding(
                get: { expandedSingleRecordPanels.contains(panel.id) },
                set: { expanded in
                    if expanded { expandedSingleRecordPanels.insert(panel.id) }
                    else { expandedSingleRecordPanels.remove(panel.id) }
                }
            )
        ) {
            VStack(spacing: 10) {
                ForEach(panel.singleRecordLines) { line in
                    statusRow(line)
                }
            }
            .padding(.top, 6)
        } label: {
            HStack(spacing: 6) {
                Text("单次记录 · 待复查对比（\(panel.singleRecordLines.count) 项\(itemLabel)）")
                if abnormalCount > 0 {
                    Text("\(abnormalCount) 项异常")
                        .font(.caption2.bold())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Theme.warning.opacity(0.15))
                        .foregroundStyle(Theme.warning)
                        .clipShape(Capsule())
                }
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(Theme.textSecondary)
        }
    }

    private func stableDisclosure(_ panel: HealthMetricTrendEngine.TrendPanel, itemLabel: String) -> some View {
        DisclosureGroup(
            isExpanded: Binding(
                get: { expandedStablePanels.contains(panel.id) },
                set: { expanded in
                    if expanded { expandedStablePanels.insert(panel.id) }
                    else { expandedStablePanels.remove(panel.id) }
                }
            )
        ) {
            VStack(spacing: 8) {
                ForEach(panel.stableLines) { line in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(line.plainTitle)
                                .font(.caption.weight(.medium))
                            Text(line.relatedTo)
                                .font(.caption2)
                                .foregroundStyle(Theme.textSecondary)
                                .lineLimit(1)
                        }
                        Spacer()
                        Text("保持正常")
                            .font(.caption2)
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
            }
            .padding(.top, 6)
        } label: {
            Text("保持正常的\(itemLabel)（\(panel.stableLines.count) 项，默认收起）")
                .font(.caption.weight(.medium))
                .foregroundStyle(Theme.textSecondary)
        }
    }

    private var disclaimer: some View {
        Text(RiskFlag.medicalDisclaimer)
            .font(.caption)
            .foregroundStyle(Theme.textSecondary)
            .frame(maxWidth: .infinity, alignment: .center)
    }
}

#Preview {
    NavigationStack {
        HealthMetricTrendView()
    }
    .modelContainer(for: [Report.self, HealthMetric.self], inMemory: true)
}
