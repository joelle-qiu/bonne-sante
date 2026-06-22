import SwiftUI
import SwiftData

/// 报告 OCR 强制校对页
/// @author jiali.qiu
struct ReportVerifyView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme

    let draft: ReportImporter.ImportDraft
    var stagedSegment: StagedSegmentInfo?
    var onStagedSegmentSaved: (([UUID]) -> Void)?
    var onFinished: (() -> Void)?

    @State private var metrics: [ReportImporter.DraftMetric]
    @State private var findings: [ReportImporter.DraftFinding]
    @State private var recommendationsText: String
    @State private var isSaving = false
    @State private var saveProgress: Double = 0.05
    @State private var saveStatus = "正在入库…"
    @State private var errorMessage: String?
    @State private var summaryRoute: ImportSummaryRoute?
    @State private var showSanitizedPreview = false
    @State private var abnormalBatchConfirmed = false
    @State private var showSaveConfirm = false
    @State private var showAllNormalMetrics = false

    init(
        draft: ReportImporter.ImportDraft,
        stagedSegment: StagedSegmentInfo? = nil,
        onStagedSegmentSaved: (([UUID]) -> Void)? = nil,
        onFinished: (() -> Void)? = nil
    ) {
        self.draft = draft
        self.stagedSegment = stagedSegment
        self.onStagedSegmentSaved = onStagedSegmentSaved
        self.onFinished = onFinished
        _metrics = State(initialValue: draft.metrics.isEmpty
            ? [ReportImporter.DraftMetric(name: "", valueText: "")]
            : draft.metrics)
        _findings = State(initialValue: Self.filterFindingsForDisplay(draft.findings))
        _recommendationsText = State(initialValue: draft.recommendations.joined(separator: "\n"))
    }

    /// 大文件导入：仅展示需关注项，正常指标折叠说明（避免 List 渲染数百行卡死）
    private var isCompactVerify: Bool {
        if stagedSegment != nil, validMetrics.count + validFindings.count > 36 {
            return true
        }
        return validMetrics.count + validFindings.count > 80
    }

    private var recommendationBullets: [String] {
        draft.recommendations
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.count >= 4 }
    }

    private var hasFollowUpPreview: Bool {
        !draft.assessmentSummary.isEmpty || !recommendationBullets.isEmpty
    }

    private static func filterFindingsForDisplay(_ raw: [ReportImporter.DraftFinding]) -> [ReportImporter.DraftFinding] {
        raw.filter { finding in
            if ReportMetricNormalizer.hasClinicalFindingContent(finding) { return true }
            let blob = finding.detail.isEmpty ? finding.title : "\(finding.title) \(finding.detail)"
            return !ReportMetricNormalizer.isInsignificantImagingLine(blob)
        }
    }

    private var hasSavableContent: Bool {
        metrics.contains { !$0.name.trimmingCharacters(in: .whitespaces).isEmpty }
            || findings.contains { !$0.title.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    private var validMetrics: [ReportImporter.DraftMetric] {
        metrics.filter { !$0.name.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    private var validFindings: [ReportImporter.DraftFinding] {
        findings.filter { !$0.title.trimmingCharacters(in: CharacterSet.whitespaces).isEmpty }
    }

    private var abnormalMetrics: [ReportImporter.DraftMetric] {
        validMetrics.filter(\.isAbnormal)
    }

    private var abnormalFindings: [ReportImporter.DraftFinding] {
        validFindings.filter(\.isAbnormal)
    }

    private var abnormalStandaloneMetrics: [ReportImporter.DraftMetric] {
        validMetrics.filter { $0.isAbnormal && $0.panelName.isEmpty }
    }

    private var abnormalMetricPanels: [NormalMetricPanel] {
        let abnormals = validMetrics.filter { $0.isAbnormal && !$0.panelName.isEmpty }
        var buckets: [String: [ReportImporter.DraftMetric]] = [:]
        for metric in abnormals {
            let section = metric.section.isEmpty
                ? ReportMetricCategory.inferSection(name: metric.name, valueText: metric.valueText)
                : metric.section
            let key = "\(section)|\(metric.panelName)"
            buckets[key, default: []].append(metric)
        }
        return buckets.map { key, items in
            let parts = key.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false)
            let section = parts.first.map(String.init) ?? ReportMetricCategory.fallbackSection
            let panelName = parts.count > 1 ? String(parts[1]) : items.first?.panelName ?? ""
            return NormalMetricPanel(
                id: key,
                section: section,
                panelName: panelName,
                items: items.sorted {
                    if $0.severityRank != $1.severityRank { return $0.severityRank > $1.severityRank }
                    return $0.name.localizedStandardCompare($1.name) == .orderedAscending
                }
            )
        }
        .sorted {
            if $0.section != $1.section { return $0.section.localizedStandardCompare($1.section) == .orderedAscending }
            return $0.panelName.localizedStandardCompare($1.panelName) == .orderedAscending
        }
    }

    /// 需关注条目数（发现 + 异常组合 + 独立异常指标，非拆分后的子项总数）
    private var abnormalAttentionCount: Int {
        abnormalFindings.count + abnormalMetricPanels.count + abnormalStandaloneMetrics.count
    }

    private var abnormalCount: Int {
        abnormalAttentionCount
    }

    private var abnormalMetricsSorted: [ReportImporter.DraftMetric] {
        abnormalStandaloneMetrics.sorted {
            if $0.severityRank != $1.severityRank { return $0.severityRank > $1.severityRank }
            return $0.name < $1.name
        }
    }

    private var abnormalFindingsSorted: [ReportImporter.DraftFinding] {
        abnormalFindings.sorted {
            if $0.severityRank != $1.severityRank { return $0.severityRank > $1.severityRank }
            return $0.title < $1.title
        }
    }

    private var groupedNormalFindings: [(title: String, items: [ReportImporter.DraftFinding])] {
        ReportMetricCategory.grouped(validFindings.filter { !$0.isAbnormal }) { finding in
            ReportMetricCategory.sectionForFinding(category: finding.category)
        }
    }

    private var groupedNormalMetrics: [(title: String, items: [ReportImporter.DraftMetric])] {
        ReportMetricCategory.grouped(validMetrics.filter { !$0.isAbnormal && $0.panelName.isEmpty }) { metric in
            metric.section.isEmpty
                ? ReportMetricCategory.inferSection(name: metric.name, valueText: metric.valueText)
                : metric.section
        }
    }

    private var normalMetricPanels: [NormalMetricPanel] {
        let normals = validMetrics.filter { !$0.isAbnormal && !$0.panelName.isEmpty }
        var buckets: [String: [ReportImporter.DraftMetric]] = [:]
        for metric in normals {
            let section = metric.section.isEmpty
                ? ReportMetricCategory.inferSection(name: metric.name, valueText: metric.valueText)
                : metric.section
            let key = "\(section)|\(metric.panelName)"
            buckets[key, default: []].append(metric)
        }
        return buckets.map { key, items in
            let parts = key.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false)
            let section = parts.first.map(String.init) ?? ReportMetricCategory.fallbackSection
            let panelName = parts.count > 1 ? String(parts[1]) : items.first?.panelName ?? ""
            return NormalMetricPanel(
                id: key,
                section: section,
                panelName: panelName,
                items: items.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            )
        }
        .sorted {
            if $0.section != $1.section { return $0.section.localizedStandardCompare($1.section) == .orderedAscending }
            return $0.panelName.localizedStandardCompare($1.panelName) == .orderedAscending
        }
    }

    private struct NormalMetricPanel: Identifiable {
        let id: String
        let section: String
        let panelName: String
        let items: [ReportImporter.DraftMetric]

        var displayName: String {
            ReportMetricCategory.professionalPanelName(panelName)
        }
    }

    private var allAbnormalConfirmed: Bool {
        abnormalCount == 0 || abnormalBatchConfirmed
    }

    private var pendingConfirmCount: Int {
        abnormalBatchConfirmed ? 0 : abnormalCount
    }

    @State private var showRecommendationsEditor = false

    private var navigationTitleText: String {
        if let stagedSegment {
            return "校对（\(stagedSegment.index)/\(stagedSegment.total)）"
        }
        return "校对报告"
    }

    private var confirmActionTitle: String {
        stagedSegment == nil ? "确认入库" : "确认本段"
    }

    private var confirmButtonTitle: String {
        if allAbnormalConfirmed {
            return stagedSegment == nil ? "确认入库" : "确认本段入库"
        }
        return "请先确认 \(pendingConfirmCount) 项需关注"
    }

    var body: some View {
        List {
            if let stagedSegment {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Label(
                            "分段导入 · 第 \(stagedSegment.index)/\(stagedSegment.total) 段",
                            systemImage: "square.stack.3d.up"
                        )
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.primaryDark)
                        Text(stagedSegment.label)
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                        Text("确认本段入库后自动进入下一段，与手动分段粘贴相同。")
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
            }

            Section {
                verifySummaryHeader
            }

            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .foregroundStyle(Theme.warning)
                }
            }

            if abnormalCount > 0 {
                Section {
                    if abnormalBatchConfirmed {
                        Label("已确认全部 \(abnormalAttentionCount) 项需关注", systemImage: "checkmark.seal.fill")
                            .font(.subheadline)
                            .foregroundStyle(Theme.primaryDark)
                    } else {
                        Button {
                            abnormalBatchConfirmed = true
                        } label: {
                            Label("一键确认全部 \(abnormalAttentionCount) 项需关注", systemImage: "checkmark.circle")
                                .font(.headline)
                                .foregroundStyle(Theme.primaryDark)
                        }
                    }
                }

                Section("需关注（\(abnormalAttentionCount) 项，按严重度排序）") {
                    ForEach(abnormalFindingsSorted) { finding in
                        findingEditor(findingID: finding.id)
                    }
                    ForEach(abnormalMetricPanels) { panel in
                        abnormalPanelEditor(panel)
                    }
                    ForEach(abnormalMetricsSorted) { metric in
                        compactAbnormalMetricEditor(metricID: metric.id)
                    }
                }
            }

            if !groupedNormalFindings.isEmpty {
                if isCompactVerify {
                    Section("正常结论（\(validFindings.filter { !$0.isAbnormal }.count) 项）") {
                        Text("大文件精简模式：正常结论将一并入库。如需逐条编辑，请拆分 JSON 后单独导入。")
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                    }
                } else {
                    ForEach(groupedNormalFindings, id: \.title) { group in
                        Section("\(group.title)（\(group.items.count) 项）") {
                            ForEach(group.items) { finding in
                                findingEditor(findingID: finding.id)
                            }
                        }
                    }
                    Section {
                        Button(role: .destructive) {
                            findings.removeAll()
                        } label: {
                            Label("清空全部检查结论", systemImage: "trash")
                        }
                        .disabled(findings.isEmpty)
                    }
                }
            }

            if isCompactVerify && !normalMetricPanels.isEmpty {
                Section("正常指标（\(validMetrics.filter { !$0.isAbnormal }.count) 项）") {
                    if showAllNormalMetrics {
                        ForEach(normalMetricPanels) { panel in
                            Section("\(panel.section) · \(panel.displayName)（\(panel.items.count) 项）") {
                                panelMetricEditor(panel)
                            }
                        }
                        ForEach(groupedNormalMetrics, id: \.title) { group in
                            Section("\(group.title)（\(group.items.count) 项）") {
                                ForEach(group.items) { metric in
                                    metricEditor(metricID: metric.id)
                                }
                            }
                        }
                    } else {
                        Text("已解析 \(validMetrics.count) 项指标，其中 \(validMetrics.filter { !$0.isAbnormal }.count) 项为正常值，入库时全部保存。")
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                        Button("展开全部正常指标") {
                            showAllNormalMetrics = true
                        }
                        .font(.caption.bold())
                    }
                }
            } else {
                ForEach(normalMetricPanels) { panel in
                    Section("\(panel.section) · \(panel.displayName)（\(panel.items.count) 项指标）") {
                        panelMetricEditor(panel)
                    }
                }

                ForEach(groupedNormalMetrics, id: \.title) { group in
                    Section("\(group.title)（\(group.items.count) 项）") {
                        ForEach(group.items) { metric in
                            metricEditor(metricID: metric.id)
                        }
                    }
                }
            }

            Section {
                Button {
                    metrics.append(ReportImporter.DraftMetric(name: "", valueText: ""))
                } label: {
                    Label("添加指标", systemImage: "plus.circle")
                }
            }

            if hasFollowUpPreview {
                Section("复查建议") {
                    if !draft.assessmentSummary.isEmpty {
                        Text(draft.assessmentSummary)
                            .font(.caption)
                            .foregroundStyle(Theme.adaptiveTextSecondary(colorScheme))
                    }
                    ForEach(recommendationBullets, id: \.self) { line in
                        Text(line)
                            .font(.caption)
                            .foregroundStyle(Theme.adaptiveTextPrimary(colorScheme))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    Text("以上为主检建议原文，入库时一并保存。仅供参考，请遵医嘱。")
                        .font(.caption2)
                        .foregroundStyle(Theme.adaptiveTextSecondary(colorScheme))
                }
            }

            if !recommendationsText.isEmpty || draft.usedAIAssist || !draft.recommendations.isEmpty {
                Section {
                    DisclosureGroup(isExpanded: $showRecommendationsEditor) {
                        TextEditor(text: $recommendationsText)
                            .frame(minHeight: 100)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("主检建议")
                                .font(.subheadline.weight(.medium))
                            if !recommendationsPreview.isEmpty {
                                Text(recommendationsPreview)
                                    .font(.caption)
                                    .foregroundStyle(Theme.textSecondary)
                                    .lineLimit(2)
                            }
                        }
                    }
                }
            }

            Section {
                sourceLabel
                if pendingConfirmCount > 0 {
                    Label("请先一键确认上方 \(pendingConfirmCount) 项异常", systemImage: "exclamationmark.circle")
                        .font(.caption)
                        .foregroundStyle(Theme.warning)
                }
                Text("异常项已置顶并按严重度排序。确认后可入库参与健康趋势分析。仅供参考，请遵医嘱。")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                if !draft.sanitizedPreview.isEmpty {
                    Button {
                        showSanitizedPreview = true
                    } label: {
                        Label("查看脱敏后发送的文本预览", systemImage: "eye")
                            .font(.caption)
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .cycleThemedPageBackground()
        .navigationTitle(navigationTitleText)
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $summaryRoute) { route in
            ReportImportSummaryView(
                reportID: route.reportID,
                savedReportCount: route.savedReportCount,
                savedReportIDs: route.savedReportIDs
            ) {
                if let onFinished {
                    onFinished()
                } else {
                    dismiss()
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(confirmActionTitle) { requestSave() }
                    .fontWeight(.semibold)
                    .disabled(isSaving || !hasSavableContent || !allAbnormalConfirmed)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Button {
                requestSave()
            } label: {
                Text(confirmButtonTitle)
                    .font(.headline)
                    .foregroundStyle(allAbnormalConfirmed ? .white : Theme.adaptiveTextPrimary(colorScheme))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(allAbnormalConfirmed ? Theme.primaryDark : Theme.primaryDark.opacity(0.12))
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.cornerRadiusButton)
                            .stroke(allAbnormalConfirmed ? Color.clear : Theme.primaryDark.opacity(0.45), lineWidth: 1.5)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadiusButton))
            }
            .disabled(isSaving || !hasSavableContent || !allAbnormalConfirmed)
            .padding(.horizontal, Theme.horizontalPadding)
            .padding(.vertical, 10)
            .background(.regularMaterial)
        }
        .alert("确认入库？", isPresented: $showSaveConfirm) {
            Button("取消", role: .cancel) {}
            Button("确认入库") { save() }
        } message: {
            Text("已确认 \(abnormalAttentionCount) 项需关注。入库后数据将参与健康趋势与风险分析。")
        }
        .overlay {
            if isSaving {
                ReportProcessingOverlay(message: saveStatus, progress: saveProgress)
            }
        }
        .sheet(isPresented: $showSanitizedPreview) {
            NavigationStack {
                ScrollView {
                    Text(draft.sanitizedPreview)
                        .font(.caption)
                        .padding()
                }
                .navigationTitle("脱敏文本预览")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("关闭") { showSanitizedPreview = false }
                    }
                }
            }
        }
    }

    private var verifySummaryHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("校对结果概览")
                .font(.headline)

            if let examDate = draft.examDate {
                Label(examDateLabel(examDate), systemImage: "calendar")
                    .font(.subheadline)
            }

            if draft.distinctVisitDates.count > 1 {
                Label(
                    "将按 \(draft.distinctVisitDates.count) 个日期分别入库（\(draft.distinctVisitDates.map { examDateLabel($0) }.joined(separator: "、"))）",
                    systemImage: "arrow.triangle.branch"
                )
                .font(.caption)
                .foregroundStyle(Theme.primary)
            }

            HStack(spacing: 16) {
                summaryChip(value: "\(validMetrics.count)", label: "指标")
                summaryChip(value: "\(abnormalAttentionCount)", label: "需关注", highlight: abnormalAttentionCount > 0)
                summaryChip(value: "\(validFindings.count)", label: "发现", highlight: validFindings.count > 0)
            }

            if !abnormalStandaloneMetrics.isEmpty || !abnormalMetricPanels.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("需关注")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Theme.textSecondary)
                    ForEach(abnormalMetricPanels.prefix(3)) { panel in
                        Text("· \(panel.displayName)：\(panel.items.map { "\($0.name) \($0.valueText)" }.joined(separator: "，"))")
                            .font(.caption)
                            .foregroundStyle(Theme.warning)
                    }
                    ForEach(abnormalStandaloneMetrics.prefix(3), id: \.id) { metric in
                        Text("· \(metric.name) \(metric.valueText)")
                            .font(.caption)
                            .foregroundStyle(Theme.warning)
                    }
                }
            }

            if !recommendationsPreview.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("主检建议摘要")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Theme.textSecondary)
                    Text(recommendationsPreview)
                        .font(.caption)
                        .lineLimit(3)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func summaryChip(value: String, label: String, highlight: Bool = false) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.title3.bold())
                .foregroundStyle(highlight ? Theme.warning : Theme.adaptiveTextPrimary(colorScheme))
            Text(label)
                .font(.caption2)
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background((highlight ? Theme.warning : Theme.primary).opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var recommendationsPreview: String {
        let text = recommendationsText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty { return text }
        return draft.recommendations.joined(separator: "\n")
    }

    private func examDateLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy年M月d日"
        return formatter.string(from: date)
    }

    private var sourceLabel: some View {
        Group {
            switch draft.sourceType {
            case "deepseek_paste":
                Label("来源：DeepSeek 网页整理", systemImage: "checkmark.seal")
            case "clinic_note":
                Label("来源：门诊手输文字", systemImage: "text.insert")
            case "ocr_clinic", "screenshot":
                Label("来源：门诊拍照 / OCR", systemImage: "camera.viewfinder")
            case "pdf":
                Label("来源：PDF / OCR", systemImage: "doc.viewfinder")
            default:
                if draft.usedAIAssist {
                    Label("DeepSeek 已辅助整理 OCR", systemImage: "sparkles")
                } else {
                    Label("来源：本地导入", systemImage: "tray.and.arrow.down")
                }
            }
        }
        .font(.caption)
        .foregroundStyle(Theme.primary)
    }

    @ViewBuilder
    private func abnormalPanelEditor(_ panel: NormalMetricPanel) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(panel.displayName)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.warning)
            ForEach(panel.items) { item in
                HStack(alignment: .top) {
                    Text(item.name)
                        .font(.caption.weight(.medium))
                    Spacer(minLength: 8)
                    Text(item.valueText)
                        .font(.caption)
                        .multilineTextAlignment(.trailing)
                }
                .foregroundStyle(Theme.adaptiveTextPrimary(colorScheme))
            }
            if let note = panel.items.first(where: { !$0.assessmentNote.isEmpty })?.assessmentNote {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(Theme.warning)
            }
            if panel.items.contains(where: { $0.severityRank > 0 }) {
                Text("关注等级 \(panel.items.map(\.severityRank).max() ?? 0)/5")
                    .font(.caption2)
                    .foregroundStyle(Theme.warning)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func compactAbnormalMetricEditor(metricID: UUID) -> some View {
        if let index = metrics.firstIndex(where: { $0.id == metricID }) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    TextField("指标", text: $metrics[index].name)
                    TextField("结果", text: $metrics[index].valueText)
                        .multilineTextAlignment(.trailing)
                        .onChange(of: metrics[index].valueText) { _, newValue in
                            metrics[index].value = Double(newValue.filter { $0.isNumber || $0 == "." }) ?? metrics[index].value
                        }
                }
                if !metrics[index].assessmentNote.isEmpty {
                    Text(metrics[index].assessmentNote)
                        .font(.caption)
                        .foregroundStyle(Theme.warning)
                }
                Toggle("标记异常", isOn: $metrics[index].isAbnormal)
                    .onChange(of: metrics[index].isAbnormal) { _, isOn in
                        if isOn { abnormalBatchConfirmed = false }
                    }
            }
            .padding(.vertical, 4)
        }
    }

    @ViewBuilder
    private func panelMetricEditor(_ panel: NormalMetricPanel) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let summary = panel.items.first?.assessmentNote, !summary.isEmpty {
                Text(summary)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.primaryDark)
            }
            Text(panel.items.map { "\($0.name) \($0.valueText)" }.joined(separator: "，"))
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
            Text("入库后将按 \(panel.items.count) 项独立指标存储，便于健康趋势对比。")
                .font(.caption2)
                .foregroundStyle(Theme.textSecondary)
            DisclosureGroup("展开编辑子项") {
                ForEach(panel.items) { item in
                    metricEditor(metricID: item.id)
                        .padding(.vertical, 4)
                }
            }
            .font(.caption)
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func metricEditor(metricID: UUID) -> some View {
        if let index = metrics.firstIndex(where: { $0.id == metricID }) {
            VStack(alignment: .leading, spacing: 8) {
                TextField("指标名称", text: $metrics[index].name)
                    .onChange(of: metrics[index].name) { _, _ in
                        ReportMetricCategory.assignSection(to: &metrics[index])
                    }
                if let hint = HealthRecordAligner.alignmentHint(forMetricName: metrics[index].name) {
                    Text(hint)
                        .font(.caption2)
                        .foregroundStyle(Theme.primaryDark)
                }
                TextField("结果（如 6.2 mmol/L）", text: $metrics[index].valueText)
                    .onChange(of: metrics[index].valueText) { _, newValue in
                        metrics[index].value = Double(newValue.filter { $0.isNumber || $0 == "." }) ?? metrics[index].value
                        ReportMetricCategory.assignSection(to: &metrics[index])
                    }
                TextField("参考范围（可选）", text: $metrics[index].referenceRange)
                Picker("章节", selection: $metrics[index].section) {
                    ForEach(ReportMetricCategory.orderedSections.map(\.title) + [ReportMetricCategory.fallbackSection], id: \.self) { title in
                        Text(title).tag(title)
                    }
                }
                Toggle("标记异常", isOn: $metrics[index].isAbnormal)
                    .onChange(of: metrics[index].isAbnormal) { _, isOn in
                        if isOn { abnormalBatchConfirmed = false }
                    }
                if metrics[index].severityRank > 0 {
                    Text("关注等级 \(metrics[index].severityRank)/5")
                        .font(.caption2)
                        .foregroundStyle(metrics[index].severityRank >= 4 ? Theme.warning : Theme.textSecondary)
                }
                if !metrics[index].assessmentNote.isEmpty {
                    Text(metrics[index].assessmentNote)
                        .font(.caption)
                        .foregroundStyle(metrics[index].isAbnormal ? Theme.warning : Theme.textSecondary)
                }
                Button(role: .destructive) {
                    metrics.remove(at: index)
                } label: {
                    Label("删除", systemImage: "trash")
                }
                .font(.caption)
            }
            .padding(.vertical, 4)
        }
    }

    @ViewBuilder
    private func findingEditor(findingID: UUID) -> some View {
        if let index = findings.firstIndex(where: { $0.id == findingID }) {
            VStack(alignment: .leading, spacing: 8) {
                TextField("类别（如 影像/妇科）", text: $findings[index].category)
                TextField("发现项", text: $findings[index].title)
                if let hint = HealthRecordAligner.alignmentHint(forFinding: findings[index]) {
                    Text(hint)
                        .font(.caption2)
                        .foregroundStyle(Theme.primaryDark)
                }
                if !findings[index].conclusion.isEmpty {
                    Label {
                        Text(findings[index].conclusion)
                    } icon: {
                        Image(systemName: "checkmark.seal")
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(findings[index].isAbnormal ? Theme.warning : Theme.primaryDark)
                } else if !findings[index].assessmentNote.isEmpty {
                    Text(findings[index].assessmentNote)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(findings[index].isAbnormal ? Theme.warning : Theme.primaryDark)
                }
                if !findings[index].detail.isEmpty, findings[index].detail != findings[index].title {
                    Text(findings[index].detail)
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                } else if findings[index].conclusion.isEmpty, findings[index].assessmentNote.isEmpty {
                    TextField("补充详情（可选）", text: $findings[index].detail)
                }
                Toggle("标记异常", isOn: $findings[index].isAbnormal)
                    .onChange(of: findings[index].isAbnormal) { _, isOn in
                        if isOn { abnormalBatchConfirmed = false }
                    }
                if findings[index].severityRank > 0 {
                    Text("关注等级 \(findings[index].severityRank)/5")
                        .font(.caption2)
                        .foregroundStyle(findings[index].severityRank >= 4 ? Theme.warning : Theme.textSecondary)
                }
                Button(role: .destructive) {
                    findings.remove(at: index)
                } label: {
                    Label("删除", systemImage: "trash")
                }
                .font(.caption)
            }
            .padding(.vertical, 4)
        }
    }

    private func requestSave() {
        guard allAbnormalConfirmed else { return }
        showSaveConfirm = true
    }

    private func save() {
        isSaving = true
        saveProgress = 0.12
        saveStatus = "正在写入报告…"
        errorMessage = nil

        let validMetrics = metrics.filter { !$0.name.trimmingCharacters(in: CharacterSet.whitespaces).isEmpty }
        let validFindings = findings.filter { !$0.title.trimmingCharacters(in: CharacterSet.whitespaces).isEmpty }
            .map { ReportMetricNormalizer.normalizeFindingPresentation($0) }
        guard !validMetrics.isEmpty || !validFindings.isEmpty else {
            errorMessage = "请至少保留一条有效指标或异常发现"
            isSaving = false
            return
        }

        Task { @MainActor in
            defer { isSaving = false }
            do {
                saveProgress = 0.45
                saveStatus = "正在保存 \(validMetrics.count) 项指标…"
                var recText = recommendationsText.trimmingCharacters(in: .whitespacesAndNewlines)
                if !draft.assessmentSummary.isEmpty, !recText.contains(draft.assessmentSummary) {
                    recText = draft.assessmentSummary + (recText.isEmpty ? "" : "\n") + recText
                }
                saveProgress = 0.72
                saveStatus = "正在更新风险提醒…"
                let reports = try HealthArchiveService.saveVerifiedReports(
                    draft: draft,
                    editedMetrics: validMetrics,
                    editedFindings: validFindings,
                    recommendationsText: recText,
                    modelContext: modelContext
                )
                guard let first = reports.first else {
                    errorMessage = "未能创建报告"
                    return
                }
                saveProgress = 1.0
                saveStatus = "入库完成"
                try? await Task.sleep(for: .milliseconds(280))
                if let onStagedSegmentSaved {
                    onStagedSegmentSaved(reports.map(\.id))
                } else {
                    summaryRoute = ImportSummaryRoute(
                        reportID: first.id,
                        savedReportCount: reports.count,
                        savedReportIDs: reports.map(\.id)
                    )
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

#Preview {
    NavigationStack {
        ReportVerifyView(
            draft: ReportImporter.ImportDraft(
                fileName: "test.pdf",
                sourceType: "pdf",
                rawText: "空腹血糖 6.3 mmol/L",
                metrics: [ReportImporter.DraftMetric(name: "空腹血糖", valueText: "6.3 mmol/L", value: 6.3, unit: "mmol/L")],
                findings: [ReportImporter.DraftFinding(category: "检验", title: "总胆固醇升高", detail: "5.57 mmol/L")],
                recommendations: ["低脂饮食，3 月复查血脂"],
                examDate: Date(),
                usedAIAssist: true,
                sanitizedPreview: "OCR 脱敏文本…"
            )
        )
    }
    .modelContainer(for: [Report.self, HealthMetric.self, RiskFlag.self], inMemory: true)
}
