import SwiftUI
import SwiftData

/// 入库后本次导入摘要：异常项、风险提醒、复查建议
/// @author jiali.qiu
struct ReportImportSummaryView: View {
    let reportID: UUID
    var savedReportCount: Int = 1
    var savedReportIDs: [UUID] = []
    var onComplete: () -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @Query(filter: #Predicate<RiskFlag> { !$0.isResolved }) private var activeRisks: [RiskFlag]

    @State private var report: Report?
    @State private var savedReports: [Report] = []
    @State private var planFeedback: String?

    private var summary: HealthProfileEngine.Summary? {
        guard let report else { return nil }
        return HealthArchiveService.importSummary(for: report)
    }

    private var savedFollowUpItems: [FollowUpRecommendationEngine.Item] {
        guard let report else { return [] }
        let lines = report.recommendationsText
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let summaryLine = lines.first(where: { $0.contains("分别于") && $0.contains("科") }) ?? ""
        let recs = lines.filter { !($0.contains("分别于") && $0.contains("科")) }
        return FollowUpRecommendationEngine.build(
            recommendations: recs,
            assessmentSummary: summaryLine
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let report, let summary {
                    header(report: report, summary: summary)
                    if !summary.abnormalGroups.isEmpty {
                        abnormalSection(summary)
                    } else if !summary.abnormalItems.isEmpty {
                        abnormalSectionLegacy(summary)
                    }
                    if !activeRisks.isEmpty {
                        risksSection(report: report)
                    } else {
                        noRiskCard
                    }
                    if !report.recommendationsText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        recommendationsSection(report.recommendationsText)
                    }
                    imagingAnchorSection(report)
                    if !savedFollowUpItems.isEmpty {
                        followUpSection(savedFollowUpItems)
                    }
                    actionsSection
                    disclaimer
                } else {
                    ProgressView("加载摘要…")
                        .frame(maxWidth: .infinity, minHeight: 200)
                }
            }
            .padding(.horizontal, Theme.horizontalPadding)
            .padding(.vertical, 16)
        }
        .cycleThemedPageBackground()
        .navigationTitle("导入摘要")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .task { await loadReport() }
    }

    private func header(report: Report, summary: HealthProfileEngine.Summary) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("报告已入库", systemImage: "checkmark.circle.fill")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Theme.brandPrimary(colorScheme))
            Text(ReportDisplayFormatter.timelineTitle(for: report))
                .font(.title2.bold())
                .foregroundStyle(Theme.adaptiveTextPrimary(colorScheme))
            Text(summary.headline)
                .font(.subheadline)
                .foregroundStyle(Theme.adaptiveTextSecondary(colorScheme))
            Text("\(report.metrics.count) 项指标已写入档案")
                .font(.caption)
                .foregroundStyle(Theme.adaptiveTextSecondary(colorScheme))
            if savedReportCount > 1 {
                Text("已按 \(savedReportCount) 个就诊日期拆分入库，可在「健康趋势」查看跨次对比。")
                    .font(.caption)
                    .foregroundStyle(Theme.link(colorScheme))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .morandiCard()
    }

    private func abnormalSection(_ summary: HealthProfileEngine.Summary) -> some View {
        AbnormalSummaryBlocks.SectionView(
            title: "本次异常指标",
            groups: summary.abnormalGroups
        )
    }

    private func abnormalSectionLegacy(_ summary: HealthProfileEngine.Summary) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("本次异常指标")
                .font(.headline)
                .foregroundStyle(Theme.adaptiveTextPrimary(colorScheme))
            ForEach(summary.abnormalItems, id: \.self) { item in
                Label(item, systemImage: "exclamationmark.circle")
                    .font(.subheadline)
                    .foregroundStyle(Theme.adaptiveWarning(colorScheme))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .morandiCard()
    }

    private func risksSection(report: Report) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("风险提醒")
                    .font(.headline)
                    .foregroundStyle(Theme.adaptiveTextPrimary(colorScheme))
                Spacer()
                Text("\(activeRisks.count) 项")
                    .font(.caption)
                    .foregroundStyle(Theme.adaptiveTextSecondary(colorScheme))
            }
            ForEach(activeRisks, id: \.id) { risk in
                RiskCard(
                    title: risk.metricName,
                    value: risk.currentValue,
                    trend: risk.trendDescription,
                    action: risk.suggestedAction,
                    severity: risk.severityLevel,
                    suggestedCheckupMonths: risk.checkupMonths,
                    department: risk.department,
                    onScheduleCheckup: { months in
                        scheduleCheckup(for: risk, months: months, lastExam: report.examDate)
                    }
                )
            }
            if let planFeedback {
                Text(planFeedback)
                    .font(.caption)
                    .foregroundStyle(Theme.adaptiveTextSecondary(colorScheme))
            }
        }
    }

    private var noRiskCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("风险评估")
                .font(.headline)
                .foregroundStyle(Theme.adaptiveTextPrimary(colorScheme))
            Text("未命中预设风险规则，请结合主检建议与医生意见。")
                .font(.subheadline)
                .foregroundStyle(Theme.adaptiveTextSecondary(colorScheme))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .morandiCard()
    }

    private func recommendationsSection(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("主检建议")
                .font(.headline)
                .foregroundStyle(Theme.adaptiveTextPrimary(colorScheme))
            Text(text)
                .font(.subheadline)
                .foregroundStyle(Theme.adaptiveTextPrimary(colorScheme))
                .lineSpacing(4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Theme.cardBackground(colorScheme))
        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadiusCard))
    }

    @ViewBuilder
    private func imagingAnchorSection(_ report: Report) -> some View {
        let sourceReports = savedReports.isEmpty ? [report] : savedReports
        let anchors = sourceReports
            .flatMap(\.metrics)
            .filter { $0.category == "异常发现" && $0.value > 0 }
            .filter {
                let key = FindingNameCanonicalizer.trendSeriesKey(for: $0) ?? ""
                return key == "imaging.lung_nodule" || key == "imaging.liver_lesion"
            }
            .sorted { $0.date < $1.date }
        if anchors.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text("影像随访尺寸")
                    .font(.headline)
                    .foregroundStyle(Theme.adaptiveTextPrimary(colorScheme))
                Text("以下尺寸由 App 从描述中提取并写入档案（含 cm→mm 换算），供健康趋势对比。")
                    .font(.caption)
                    .foregroundStyle(Theme.adaptiveTextSecondary(colorScheme))
                ForEach(anchors, id: \.id) { metric in
                    HStack(alignment: .top, spacing: 8) {
                        Text(ReportDisplayFormatter.examDateLabel(metric.date))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.departmentLabel(colorScheme))
                            .frame(width: 88, alignment: .leading)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(FindingNameCanonicalizer.plainTitle(
                                for: FindingNameCanonicalizer.trendSeriesKey(for: metric) ?? metric.name,
                                fallback: metric.name
                            ))
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(Theme.adaptiveTextPrimary(colorScheme))
                            Text(String(format: "%.1f mm", metric.value))
                                .font(.subheadline.bold())
                                .foregroundStyle(Theme.link(colorScheme))
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(Theme.brandPrimary(colorScheme).opacity(colorScheme == .dark ? 0.18 : 0.12))
            .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadiusCard))
        }
    }

    private func followUpSection(_ items: [FollowUpRecommendationEngine.Item]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("复查建议")
                .font(.headline)
                .foregroundStyle(Theme.adaptiveTextPrimary(colorScheme))
            ForEach(items.filter(\.hasBody)) { item in
                Text("· \(item.bodyText)")
                    .font(.subheadline)
                    .foregroundStyle(Theme.adaptiveTextPrimary(colorScheme))
                    .lineSpacing(3)
            }
            Text("仅供参考，请遵医嘱。")
                .font(.caption)
                .foregroundStyle(Theme.adaptiveTextSecondary(colorScheme))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Theme.cardBackground(colorScheme))
        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadiusCard))
    }

    private var actionsSection: some View {
        VStack(spacing: 12) {
            NavigationLink {
                HealthSummaryView()
            } label: {
                Label("查看完整健康摘要", systemImage: "heart.text.square")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.link(colorScheme))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Theme.brandPrimary(colorScheme).opacity(colorScheme == .dark ? 0.18 : 0.12))
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.cornerRadiusButton)
                            .stroke(Theme.link(colorScheme).opacity(0.5), lineWidth: 1.5)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadiusButton))
            }

            Button {
                onComplete()
            } label: {
                Text("完成，返回健康档案")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Theme.brandPrimary(colorScheme))
                    .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadiusButton))
            }
        }
    }

    private var disclaimer: some View {
        Text(RiskFlag.medicalDisclaimer)
            .font(.caption)
            .foregroundStyle(Theme.adaptiveTextSecondary(colorScheme))
            .frame(maxWidth: .infinity, alignment: .center)
    }

    @MainActor
    private func loadReport() async {
        let id = reportID
        var descriptor = FetchDescriptor<Report>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        report = try? modelContext.fetch(descriptor).first

        let ids = savedReportIDs.isEmpty ? [id] : savedReportIDs
        let all = try? modelContext.fetch(FetchDescriptor<Report>())
        savedReports = (all ?? []).filter { ids.contains($0.id) }
            .sorted { ReportDisplayFormatter.examDate(for: $0) < ReportDisplayFormatter.examDate(for: $1) }
    }

    private func scheduleCheckup(for risk: RiskFlag, months: Int, lastExam: Date?) {
        do {
            _ = try HealthArchiveService.setupCheckupPlan(
                from: risk,
                months: months,
                lastExam: lastExam,
                modelContext: modelContext
            )
            planFeedback = "已设置 \(months) 个月复查提醒"
        } catch {
            planFeedback = error.localizedDescription
        }
    }
}

/// 入库摘要导航路由
struct ImportSummaryRoute: Hashable, Identifiable {
    let reportID: UUID
    var savedReportCount: Int = 1
    var savedReportIDs: [UUID] = []
    var id: UUID { reportID }
}

#Preview {
    NavigationStack {
        ReportImportSummaryView(reportID: UUID(), onComplete: {})
    }
    .modelContainer(for: [Report.self, HealthMetric.self, RiskFlag.self, TodoItem.self], inMemory: true)
}
