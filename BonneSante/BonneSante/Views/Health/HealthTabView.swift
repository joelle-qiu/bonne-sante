import SwiftUI
import SwiftData

/// 健康档案 Tab
/// @author jiali.qiu
struct HealthTabView: View {
    @Query(sort: \Report.examDate, order: .reverse) private var reports: [Report]
    @Query(filter: #Predicate<RiskFlag> { !$0.isResolved }) private var activeRisks: [RiskFlag]
    @Query(sort: \CheckupPlan.nextDueDate) private var checkupPlans: [CheckupPlan]
    @Query(sort: \TodoItem.dueDate) private var todos: [TodoItem]

    @Environment(\.modelContext) private var modelContext
    @State private var showImport = false
    @State private var reportPendingDelete: Report?
    @State private var showDeleteConfirm = false
    @State private var deleteErrorMessage: String?
    @Environment(\.colorScheme) private var colorScheme

    private var verifiedReports: [Report] {
        reports.filter(\.isVerified)
    }

    private var hasTrendData: Bool {
        HealthMetricTrendEngine.verifiedReportCount(from: verifiedReports) >= 2
    }

    var body: some View {
        NavigationStack {
            Group {
                if reports.isEmpty {
                    EmptyStateView(
                        symbol: "list.clipboard",
                        title: "还没有健康档案",
                        message: "导入体检报告截图或 PDF，建立指标时间线与风险评估。",
                        actionTitle: "导入报告",
                        action: { showImport = true }
                    )
                } else {
                    reportList
                }
            }
            .cycleThemedPageBackground()
            .navigationTitle("档案")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showImport = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showImport) {
                ReportImportView()
            }
            .alert("删除报告？", isPresented: $showDeleteConfirm, presenting: reportPendingDelete) { report in
                Button("删除", role: .destructive) {
                    deleteReport(report)
                }
                Button("取消", role: .cancel) {
                    reportPendingDelete = nil
                }
            } message: { report in
                Text("将删除「\(ReportDisplayFormatter.timelineTitle(for: report))」及其 \(report.metrics.count) 条指标，风险摘要将重新计算。此操作不可撤销。")
            }
            .alert("删除失败", isPresented: Binding(
                get: { deleteErrorMessage != nil },
                set: { if !$0 { deleteErrorMessage = nil } }
            )) {
                Button("好的", role: .cancel) {}
            } message: {
                Text(deleteErrorMessage ?? "")
            }
        }
    }

    private func requestDelete(_ report: Report) {
        reportPendingDelete = report
        showDeleteConfirm = true
    }

    private func deleteReport(_ report: Report) {
        do {
            try HealthArchiveService.deleteReport(report, modelContext: modelContext)
            reportPendingDelete = nil
        } catch {
            deleteErrorMessage = error.localizedDescription
        }
    }

    private func toggleAppointmentComplete(_ item: TodoItem) {
        item.isCompleted.toggle()
        if item.isCompleted {
            TodoService.cancelNotifications(for: item.id)
        } else {
            TodoService.scheduleReminders(for: item)
        }
        try? modelContext.save()
    }

    @MainActor
    private func addAppointmentToCalendar(_ item: TodoItem) async {
        do {
            let eventID = try await CalendarService.addAppointment(for: item)
            item.calendarEventIdentifier = eventID
            try? modelContext.save()
        } catch {
            deleteErrorMessage = error.localizedDescription
        }
    }

    private var reportList: some View {
        List {
            Section {
                NavigationLink {
                    HealthSummaryView()
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("综合健康摘要")
                                .font(.headline)
                            Text("\(activeRisks.count) 项活跃提醒 · \(verifiedCount) 份已校对报告")
                                .font(.caption)
                                .foregroundStyle(Theme.textSecondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                    }
                }

                if hasTrendData {
                    NavigationLink {
                        HealthMetricTrendView()
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("健康趋势")
                                    .font(.headline)
                                Text("化验指标与检查结论变化")
                                    .font(.caption)
                                    .foregroundStyle(Theme.textSecondary)
                            }
                            Spacer()
                            Image(systemName: "chart.xyaxis.line")
                                .font(.caption)
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }
                }

                NavigationLink {
                    CheckupPlansView()
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("复查提醒")
                                .font(.headline)
                            if let next = checkupPlans.map(\.nextDueDate).filter({ $0 >= Calendar.current.startOfDay(for: Date()) }).min() {
                                Text("最近：\(ReportDisplayFormatter.examDateLabel(next)) · 共 \(checkupPlans.count) 项")
                                    .font(.caption)
                                    .foregroundStyle(Theme.textSecondary)
                            } else if checkupPlans.isEmpty {
                                Text("从风险提醒设置随访周期")
                                    .font(.caption)
                                    .foregroundStyle(Theme.textSecondary)
                            } else {
                                Text("共 \(checkupPlans.count) 项 · 含已逾期")
                                    .font(.caption)
                                    .foregroundStyle(Theme.warning)
                            }
                        }
                        Spacer()
                        Image(systemName: "calendar.badge.clock")
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                    }
                }

                NavigationLink {
                    ClinicAppointmentImportView()
                } label: {
                    Label("导入门诊预约", systemImage: "calendar.badge.plus")
                }
            }

            let openAppointments = todos.filter { $0.sourceType == .appointment && !$0.isCompleted }
            if !openAppointments.isEmpty {
                Section("门诊预约") {
                    ForEach(openAppointments, id: \.id) { item in
                        AppointmentTodoRow(
                            item: item,
                            onToggle: { toggleAppointmentComplete(item) },
                            onAddCalendar: { Task { await addAppointmentToCalendar(item) } }
                        )
                    }
                }
            }

            ForEach(ReportDisplayFormatter.groupedByYear(reports), id: \.year) { group in
                Section(group.year) {
                    ForEach(group.reports) { report in
                        NavigationLink {
                            ReportDetailView(report: report)
                        } label: {
                            ReportRow(report: report)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                requestDelete(report)
                            } label: {
                                Label("删除", systemImage: "trash")
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
    }

    private var verifiedCount: Int {
        reports.filter(\.isVerified).count
    }
}

private struct ReportRow: View {
    let report: Report

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            dateBlock
            VStack(alignment: .leading, spacing: 4) {
                Text(ReportDisplayFormatter.timelineTitle(for: report))
                    .font(.headline)
                    .foregroundStyle(Theme.textPrimary)
                Text(ReportDisplayFormatter.timelineSubtitle(for: report))
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                if let source = ReportDisplayFormatter.sourceCaption(for: report) {
                    Text(source)
                        .font(.caption2)
                        .foregroundStyle(Theme.textSecondary.opacity(0.85))
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            verificationBadge
        }
        .padding(.vertical, 6)
    }

    private var dateBlock: some View {
        VStack(spacing: 2) {
            Text(ReportDisplayFormatter.monthComponent(for: report))
                .font(.caption2.weight(.medium))
                .foregroundStyle(Theme.textSecondary)
            Text(ReportDisplayFormatter.dayComponent(for: report))
                .font(.title2.bold())
                .foregroundStyle(Theme.primaryDark)
        }
        .frame(width: 44)
        .padding(.vertical, 6)
        .background(Theme.primary.opacity(0.18))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    @ViewBuilder
    private var verificationBadge: some View {
        if report.isVerified {
            Text("已校对")
                .font(.caption2.weight(.medium))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Theme.primary.opacity(0.35))
                .clipShape(Capsule())
        } else {
            Text("待校对")
                .font(.caption2.weight(.medium))
                .foregroundStyle(Theme.warning)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Theme.warning.opacity(0.12))
                .clipShape(Capsule())
        }
    }
}

/// 单份报告详情
struct ReportDetailView: View {
    let report: Report

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var showDeleteConfirm = false
    @State private var deleteErrorMessage: String?

    private var groupedMetrics: [(title: String, items: [HealthMetric])] {
        ReportMetricCategory.grouped(report.metrics) { metric in
            if !metric.reportSection.isEmpty { return metric.reportSection }
            return ReportMetricCategory.inferSection(name: metric.name, valueText: metric.valueText)
        }
    }

    private var recommendationsText: String {
        report.recommendationsText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        List {
            if !recommendationsText.isEmpty {
                Section("主检建议") {
                    Text(recommendationsText)
                        .font(.subheadline)
                        .foregroundStyle(Theme.textPrimary)
                }
            }

            if report.isVerified, verifiedReportCount >= 2 {
                Section {
                    NavigationLink {
                        HealthMetricTrendView(
                            focusPanelId: focusPanelIdForFirstAbnormal,
                            focusLineId: focusLineIdForFirstAbnormal
                        )
                    } label: {
                        Label("查看健康趋势", systemImage: "chart.xyaxis.line")
                    }
                }
            }

            ForEach(groupedMetrics, id: \.title) { group in
                Section(group.title) {
                    ForEach(group.items, id: \.id) { metric in
                        metricRow(metric)
                    }
                }
            }
        }
        .navigationTitle(ReportDisplayFormatter.detailTitle(for: report))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button(role: .destructive) {
                        showDeleteConfirm = true
                    } label: {
                        Label("删除报告", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .alert("删除报告？", isPresented: $showDeleteConfirm) {
            Button("删除", role: .destructive) {
                performDelete()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("将删除本报告及其 \(report.metrics.count) 条指标，风险摘要将重新计算。此操作不可撤销。")
        }
        .alert("删除失败", isPresented: Binding(
            get: { deleteErrorMessage != nil },
            set: { if !$0 { deleteErrorMessage = nil } }
        )) {
            Button("好的", role: .cancel) {}
        } message: {
            Text(deleteErrorMessage ?? "")
        }
    }

    private func performDelete() {
        do {
            try HealthArchiveService.deleteReport(report, modelContext: modelContext)
            dismiss()
        } catch {
            deleteErrorMessage = error.localizedDescription
        }
    }

    @Query(filter: #Predicate<Report> { $0.isVerified }) private var verifiedReports: [Report]

    private var verifiedReportCount: Int { verifiedReports.count }

    private var focusPanelIdForFirstAbnormal: String? {
        guard let metric = HealthMetricTrendEngine.highlightMetrics(from: report).first else { return nil }
        return trendFocusPanelId(for: metric)
    }

    private var focusLineIdForFirstAbnormal: String? {
        guard let metric = HealthMetricTrendEngine.highlightMetrics(from: report).first else { return nil }
        return trendFocusLineId(for: metric)
    }

    private func trendFocusPanelId(for metric: HealthMetric) -> String? {
        if metric.category == "异常发现" {
            return HealthFindingTrendEngine.inferPanelId(forFindingName: metric.name)
        }
        return HealthMetricTrendEngine.inferPanelId(forMetricName: metric.name)
    }

    private func trendFocusLineId(for metric: HealthMetric) -> String? {
        if metric.category == "异常发现" {
            guard let key = FindingNameCanonicalizer.canonicalKey(for: metric) else { return nil }
            return FindingNameCanonicalizer.normalizedTrendKey(key, metric: metric)
        }
        let key = MetricNameCanonicalizer.canonicalKey(for: metric.name)
        return key.hasPrefix("raw.") ? nil : key
    }

    private func canLinkMetricToTrend(_ metric: HealthMetric) -> Bool {
        report.isVerified && verifiedReportCount >= 2 && trendFocusLineId(for: metric) != nil
    }

    @ViewBuilder
    private func metricRow(_ metric: HealthMetric) -> some View {
        HStack(alignment: .top, spacing: 8) {
            metricRowContent(metric)
            if canLinkMetricToTrend(metric) {
                NavigationLink {
                    HealthMetricTrendView(
                        focusPanelId: trendFocusPanelId(for: metric),
                        focusLineId: trendFocusLineId(for: metric)
                    )
                } label: {
                    Image(systemName: "chart.xyaxis.line")
                        .font(.body)
                        .foregroundStyle(Theme.primaryDark)
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private func metricRowContent(_ metric: HealthMetric) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(metric.name)
                    .font(.headline)
                if !metric.referenceRange.isEmpty, metric.category != "异常发现" {
                    Text("参考：\(metric.referenceRange)")
                        .font(.caption2)
                        .foregroundStyle(Theme.textSecondary)
                } else if metric.category == "异常发现", !metric.referenceRange.isEmpty {
                    Text("类别：\(metric.referenceRange)")
                        .font(.caption2)
                        .foregroundStyle(Theme.textSecondary)
                }
                if !metric.assessmentNote.isEmpty {
                    let note = ReportMetricNormalizer.dedupeAssessmentNote(metric.assessmentNote)
                    if let conclusion = conclusionLine(for: metric),
                       !metric.valueText.contains(conclusion.replacingOccurrences(of: "结论：", with: "")) {
                        Text(conclusion)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(metric.isAbnormal ? Theme.warning : Theme.primaryDark)
                    } else if !note.hasPrefix("结论："), !note.hasPrefix("结论:") {
                        Text(note)
                            .font(.caption2)
                            .foregroundStyle(Theme.textSecondary)
                    } else if !metric.valueText.contains(note) {
                        Text(note)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(metric.isAbnormal ? Theme.warning : Theme.primaryDark)
                    }
                }
                if metric.severityRank > 0 {
                    Text("关注等级 \(metric.severityRank)/5")
                        .font(.caption2)
                        .foregroundStyle(metric.severityRank >= 4 ? Theme.warning : Theme.textSecondary)
                }
            }
            Spacer(minLength: 12)
            Text(displayValue(for: metric))
                .font(.subheadline.bold())
                .multilineTextAlignment(.trailing)
                .foregroundStyle(metric.isAbnormal ? Theme.warning : Theme.textPrimary)
        }
    }

    private func displayValue(for metric: HealthMetric) -> String {
        let valueText = metric.valueText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !valueText.isEmpty {
            if metric.value != 0 && isQualitativeOnlyValueText(valueText) {
                return formattedNumericMetricValue(metric)
            }
            return metric.valueText
        }
        if metric.value != 0 {
            return formattedNumericMetricValue(metric)
        }
        return "—"
    }

    /// 定性结果文案（正常/阴性等）不应遮盖已解析的数值
    private func isQualitativeOnlyValueText(_ valueText: String) -> Bool {
        let trimmed = valueText.trimmingCharacters(in: .whitespacesAndNewlines)
        let qualitative = ["正常", "阴性", "阳性", "未见", "未查见", "neg", "normal", "未见明显异常"]
        if qualitative.contains(trimmed) { return true }
        if trimmed.hasPrefix("正常，") || trimmed.hasPrefix("正常,") { return true }
        return trimmed.range(of: #"^\d"#, options: .regularExpression) == nil
            && trimmed.range(of: #"[\d.]+"#, options: .regularExpression) == nil
    }

    private func formattedNumericMetricValue(_ metric: HealthMetric) -> String {
        let text = metric.value.truncatingRemainder(dividingBy: 1) == 0
            ? String(format: "%.0f", metric.value)
            : String(metric.value)
        return metric.unit.isEmpty ? text : "\(text) \(metric.unit)"
    }

    /// 从 assessmentNote 提取「结论：…」行（入库时 valueText 可能已含结论）
    private func conclusionLine(for metric: HealthMetric) -> String? {
        let note = ReportMetricNormalizer.dedupeAssessmentNote(metric.assessmentNote)
        if note.hasPrefix("结论：") || note.hasPrefix("结论:") {
            return note
        }
        return nil
    }
}

#Preview {
    HealthTabView()
        .modelContainer(for: [Report.self, HealthMetric.self, RiskFlag.self], inMemory: true)
}
