import SwiftUI

/// 分段导入会话（多段 JSON 逐段校对）
struct StagedImportSession: Identifiable {
    let id = UUID()
    let payloads: [ReportPasteImporter.StagedSegmentPayload]
}

/// 当前分段信息（校对页展示）
struct StagedSegmentInfo: Hashable {
    let index: Int
    let total: Int
    let label: String
}

/// 多段报告导入：解析后按时间段逐段对齐、校对、入库
/// @author jiali.qiu
struct StagedImportFlowView: View {
    let payloads: [ReportPasteImporter.StagedSegmentPayload]
    let onComplete: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @State private var currentIndex = 0
    @State private var readyDraft: ReportImporter.ImportDraft?
    @State private var isPreparing = true
    @State private var prepareStatus = "正在准备本段…"
    @State private var prepareProgress: Double = 0.1
    @State private var savedReportIDs: [UUID] = []
    @State private var showFinalSummary = false

    private var segmentInfo: StagedSegmentInfo {
        let payload = payloads[currentIndex]
        return StagedSegmentInfo(
            index: currentIndex + 1,
            total: payloads.count,
            label: payload.label
        )
    }

    var body: some View {
        NavigationStack {
            flowContent
        }
    }

    @ViewBuilder
    private var flowContent: some View {
        Group {
            if showFinalSummary, let lastID = savedReportIDs.last {
                ReportImportSummaryView(
                    reportID: lastID,
                    savedReportCount: savedReportIDs.count,
                    savedReportIDs: savedReportIDs,
                    onComplete: finishAll
                )
            } else if let readyDraft, !isPreparing {
                ReportVerifyView(
                    draft: readyDraft,
                    stagedSegment: segmentInfo,
                    onStagedSegmentSaved: handleSegmentSaved,
                    onFinished: finishAll
                )
                .id(currentIndex)
            } else {
                preparingPlaceholder
            }
        }
        .task(id: currentIndex) {
            guard !showFinalSummary else { return }
            await prepareCurrentSegment()
        }
    }

    private var preparingPlaceholder: some View {
        ZStack {
            CycleThemedBackground()
                .ignoresSafeArea()
            VStack(spacing: 16) {
                ProgressView()
                    .controlSize(.large)
                Text(prepareStatus)
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                Text("第 \(currentIndex + 1)/\(payloads.count) 段 · \(payloads[currentIndex].label)")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
    }

    @MainActor
    private func prepareCurrentSegment() async {
        isPreparing = true
        readyDraft = nil
        prepareProgress = 0.1
        prepareStatus = "正在准备第 \(currentIndex + 1)/\(payloads.count) 段…"

        let payload = payloads[currentIndex]
        let draft = await ReportPasteImporter.prepareDraftForVerify(
            from: payload,
            onProgress: { value, message in
                Task { @MainActor in
                    prepareProgress = value
                    prepareStatus = message
                }
            }
        )
        readyDraft = draft
        isPreparing = false
    }

    @MainActor
    private func handleSegmentSaved(reportIDs: [UUID]) {
        savedReportIDs.append(contentsOf: reportIDs)
        if currentIndex + 1 < payloads.count {
            isPreparing = true
            readyDraft = nil
            currentIndex += 1
        } else {
            showFinalSummary = true
        }
    }

    private func finishAll() {
        onComplete()
        dismiss()
    }
}
