import SwiftUI
import SwiftData

/// 综合健康摘要
/// @author jiali.qiu
struct HealthSummaryView: View {
    @Query(filter: #Predicate<Report> { $0.isVerified }, sort: \Report.examDate, order: .reverse)
    private var reports: [Report]

    @Query(filter: #Predicate<RiskFlag> { !$0.isResolved })
    private var activeRisks: [RiskFlag]

    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme

    @State private var summary: HealthProfileEngine.Summary?
    @State private var isLoadingSummary = true

    private var summaryTaskToken: String {
        reports.map(\.id.uuidString).joined(separator: "-") + "-\(activeRisks.count)"
    }

    var body: some View {
        Group {
            if isLoadingSummary {
                VStack(spacing: 16) {
                    ProgressView(value: loadingProgress)
                        .progressViewStyle(.linear)
                        .tint(Theme.primaryDark)
                        .frame(maxWidth: 200)
                    Text("正在汇总 \(reports.count) 份报告…")
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let summary {
                summaryScrollContent(summary)
            } else {
                ContentUnavailableView(
                    "暂无摘要",
                    systemImage: "heart.text.square",
                    description: Text("导入并校对报告后将在此显示健康摘要。")
                )
            }
        }
        .cycleThemedPageBackground()
        .navigationTitle("健康摘要")
        .task(id: summaryTaskToken) {
            await reloadSummary()
        }
    }

    @State private var loadingProgress: Double = 0.08

    private func summaryScrollContent(_ summary: HealthProfileEngine.Summary) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                summaryHeader(summary)
                if !summary.dietaryNotes.isEmpty {
                    dietarySection(summary)
                }
                if !activeRisks.isEmpty {
                    risksSection
                } else {
                    Text("当前无活跃风险提醒")
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                        .morandiCard()
                }
                disclaimer
            }
            .padding(.horizontal, Theme.horizontalPadding)
            .padding(.vertical, 16)
        }
    }

    @MainActor
    private func reloadSummary() async {
        isLoadingSummary = true
        loadingProgress = 0.12
        guard !reports.isEmpty else {
            summary = nil
            isLoadingSummary = false
            return
        }
        loadingProgress = 0.35
        _ = try? HealthArchiveService.refreshRiskAnalysis(modelContext: modelContext)
        let snapshot = HealthProfileEngine.snapshotFromReports(reports)
        loadingProgress = 0.55
        let built = await HealthProfileEngine.buildSummaryAsync(snapshot: snapshot)
        loadingProgress = 1.0
        summary = built
        isLoadingSummary = false
    }

    private func summaryHeader(_ summary: HealthProfileEngine.Summary) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(summary.headline)
                .font(.title3.bold())
            if summary.abnormalGroups.isEmpty && summary.abnormalItems.isEmpty {
                Text("已导入 \(reports.count) 份已校对报告")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
            } else if !summary.abnormalGroups.isEmpty {
                AbnormalSummaryBlocks.SectionView(
                    title: "异常指标",
                    groups: summary.abnormalGroups,
                    compact: true
                )
                .padding(.top, 4)
            } else {
                Text("异常指标")
                    .font(.headline)
                    .padding(.top, 4)
                ForEach(summary.abnormalItems, id: \.self) { item in
                    Label(item, systemImage: "circle.fill")
                        .font(.caption)
                        .labelStyle(.titleAndIcon)
                        .symbolRenderingMode(.multicolor)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .morandiCard()
    }

    private func dietarySection(_ summary: HealthProfileEngine.Summary) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("饮食联动建议")
                .font(.headline)
            ForEach(summary.dietaryNotes, id: \.self) { note in
                Text("· \(note)")
                    .font(.subheadline)
            }
            if let protein = summary.proteinFloorGrams {
                Text("· 蛋白质建议下限：\(String(format: "%.1f", protein)) g/kg 体重")
                    .font(.subheadline)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .morandiCard()
    }

    private var risksSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("风险提醒")
                .font(.headline)
            Text("与上方异常指标按科室对齐；可设置复查提醒与本地通知。")
                .font(.caption)
                .foregroundStyle(Theme.adaptiveTextSecondary(colorScheme))
            ForEach(groupedActiveRisks, id: \.department) { group in
                if groupedActiveRisks.count > 1 {
                    Text(group.department)
                        .font(.subheadline.bold())
                        .foregroundStyle(Theme.departmentLabel(colorScheme))
                        .padding(.top, 4)
                }
                ForEach(group.risks, id: \.id) { risk in
                    RiskCard(
                        title: risk.metricName,
                        value: risk.currentValue,
                        trend: risk.trendDescription,
                        action: risk.suggestedAction,
                        severity: risk.severityLevel,
                        suggestedCheckupMonths: risk.checkupMonths,
                        department: risk.department,
                        onScheduleCheckup: { months in
                            let lastExam = reports.first?.examDate
                            _ = try? HealthArchiveService.setupCheckupPlan(
                                from: risk,
                                months: months,
                                lastExam: lastExam,
                                modelContext: modelContext
                            )
                        }
                    )
                }
            }
        }
    }

    private struct RiskDepartmentGroup {
        let department: String
        let risks: [RiskFlag]
    }

    private var groupedActiveRisks: [RiskDepartmentGroup] {
        let order = ["妇科", "泌尿科", "骨科康复", "胸外科", "肝胆外科", "内分泌科", "影像科", "心血管科", "口腔科", ""]
        let grouped = Dictionary(grouping: activeRisks) { $0.department.isEmpty ? "其他" : $0.department }
        return order.compactMap { dept -> RiskDepartmentGroup? in
            let key = dept.isEmpty ? "其他" : dept
            guard let risks = grouped[key], !risks.isEmpty else { return nil }
            return RiskDepartmentGroup(department: key, risks: risks)
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
        HealthSummaryView()
    }
    .modelContainer(for: [Report.self, HealthMetric.self, RiskFlag.self], inMemory: true)
}
