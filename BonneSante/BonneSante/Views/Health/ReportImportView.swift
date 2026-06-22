import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import UIKit

/// 报告导入：DeepSeek JSON / 门诊 OCR / 手输文字
/// @author jiali.qiu
struct ReportImportView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @State private var photoItem: PhotosPickerItem?
    @State private var verifyDraft: ReportImporter.ImportDraft?
    @State private var stagedSession: StagedImportSession?
    @State private var isProcessing = false
    @State private var errorMessage: String?
    @State private var showPDFImporter = false
    @State private var showJSONFileImporter = false
    @State private var processingStatus = "正在处理…"
    @State private var processingProgress: Double = 0.05

    @State private var pastedText = ""
    @State private var clinicNoteText = ""
    @State private var promptCopied = false
    @State private var showDeepSeekWorkflow = false
    @State private var clinicErrorMessage: String?

    @State private var showingCamera = false
    @State private var cameraImage: UIImage?
    @State private var showingCameraAlert = false
    @State private var isImportingJSONFile = false

    private var isCameraAvailable: Bool {
        UIImagePickerController.isSourceTypeAvailable(.camera)
    }

    private var trimmedPaste: String {
        pastedText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedClinicNote: String {
        clinicNoteText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canParseJSON: Bool {
        !trimmedPaste.isEmpty
    }

    private var canParseClinicNote: Bool {
        !trimmedClinicNote.isEmpty
    }

    private var isJSONFileLoading: Bool {
        isImportingJSONFile && isProcessing
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    pageIntro

                    deepSeekSection
                    clinicSection
                }
                .padding(.horizontal, Theme.horizontalPadding)
                .padding(.vertical, 16)
            }
            .cycleThemedPageBackground()
            .navigationTitle("导入报告")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
            .navigationDestination(item: $verifyDraft) { item in
                ReportVerifyView(draft: item, onFinished: { dismiss() })
            }
            .fullScreenCover(item: $stagedSession) { session in
                StagedImportFlowView(payloads: session.payloads, onComplete: { dismiss() })
            }
            .overlay {
                if isProcessing {
                    ReportProcessingOverlay(message: processingStatus, progress: processingProgress)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: isProcessing)
            .onChange(of: photoItem) { _, newItem in
                guard let newItem else { return }
                Task { await importPhoto(newItem) }
            }
            .onChange(of: cameraImage) { _, image in
                guard let image else { return }
                Task { await importCapturedImage(image) }
            }
            .sheet(isPresented: $showingCamera) {
                CameraView(image: $cameraImage)
            }
            .alert("相机不可用", isPresented: $showingCameraAlert) {
                Button("好", role: .cancel) {}
            } message: {
                Text("请使用相册选择门诊化验单或结论截图。")
            }
            .fileImporter(
                isPresented: $showPDFImporter,
                allowedContentTypes: [.pdf],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    guard let url = urls.first else { return }
                    Task { await importPDF(url) }
                case .failure(let error):
                    clinicErrorMessage = error.localizedDescription
                }
            }
            .fileImporter(
                isPresented: $showJSONFileImporter,
                allowedContentTypes: [.json, .plainText],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    guard let url = urls.first else { return }
                    beginProcessing("已选择文件，正在读取…")
                    isImportingJSONFile = true
                    Task { await importJSONFile(url) }
                case .failure(let error):
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    // MARK: - Layout

    private var pageIntro: some View {
        Text("报告文件不会从本 App 上传。粘贴或识别后先预览，再进入校对入库。")
            .font(.subheadline)
            .foregroundStyle(Theme.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var deepSeekSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader(
                icon: "doc.text.magnifyingglass",
                title: "DeepSeek 整理结果",
                subtitle: "粘贴 JSON，或选择本地 .json 文件（支持多段 visitDate）"
            )

            importTextEditor(text: $pastedText, minHeight: 140, monospaced: true)
                .disabled(isProcessing)

            HStack(spacing: 10) {
                if isJSONFileLoading {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text(processingStatus)
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Theme.primary.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadiusButton, style: .continuous))
                } else {
                    outlineButton(title: "选择 JSON 文件", icon: "doc.badge.plus") {
                        showJSONFileImporter = true
                    }
                }
            }

            if let preview = parsePreviewText, !isProcessing {
                previewChip(preview, detail: parsePreviewExamDate.map { "体检日期 \($0)" })
            }

            if let errorMessage {
                errorLabel(errorMessage)
            }

            primaryButton(
                title: "解析并进入校对",
                icon: "text.badge.checkmark",
                enabled: canParseJSON && !isProcessing,
                action: parsePaste
            )

            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showDeepSeekWorkflow.toggle()
                }
            } label: {
                HStack {
                    Text("DeepSeek 操作步骤")
                        .font(.subheadline.weight(.medium))
                    Spacer()
                    Image(systemName: showDeepSeekWorkflow ? "chevron.up" : "chevron.down")
                        .font(.caption.weight(.semibold))
                }
                .foregroundStyle(Theme.primaryDark)
            }
            .buttonStyle(.plain)

            if showDeepSeekWorkflow {
                workflowSteps
            }
        }
        .morandiCard()
    }

    private var clinicSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader(
                icon: "cross.case",
                title: "门诊记录 / 本地 OCR",
                subtitle: "化验单、B 超结论等零散文字；识别后自动对齐档案指标"
            )

            importTextEditor(text: $clinicNoteText, minHeight: 120, monospaced: false)

            Text("示例：LDL 3.52 mmol/L · 诊断：高脂血症 · 超声：子宫肌瘤 15mm")
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)

            if let preview = clinicPreviewText {
                previewChip(preview, detail: clinicPreviewExamDate.map { "识别日期 \($0)" })
            }

            if let clinicErrorMessage {
                errorLabel(clinicErrorMessage)
            }

            primaryButton(
                title: "解析门诊文字并校对",
                icon: "text.insert",
                enabled: canParseClinicNote && !isProcessing,
                action: parseClinicNote
            )

            Divider()

            Text("或拍照 / 选图 / PDF")
                .font(.caption.weight(.medium))
                .foregroundStyle(Theme.textSecondary)

            HStack(spacing: 10) {
                outlineButton(title: "拍照", icon: "camera") {
                    if isCameraAvailable {
                        showingCamera = true
                    } else {
                        showingCameraAlert = true
                    }
                }
                PhotosPicker(selection: $photoItem, matching: .images) {
                    outlineLabel(title: "相册", icon: "photo")
                }
                .disabled(isProcessing)
            }

            outlineButton(title: "选择 PDF", icon: "doc.fill") {
                showPDFImporter = true
            }
        }
        .morandiCard()
    }

    private var workflowSteps: some View {
        VStack(alignment: .leading, spacing: 12) {
            stepRow(number: 1, title: "复制整理指令", detail: "含严重度分级、visitDate 与趋势对比要求")
            stepRow(number: 2, title: "打开 DeepSeek 网页", detail: "上传 PDF/截图或粘贴多次门诊 Markdown")
            stepRow(number: 3, title: "复制 JSON 回复", detail: "每条检查须带 visitDate；回到本页粘贴解析")

            HStack(spacing: 10) {
                Button {
                    UIPasteboard.general.string = ReportDeepSeekPastePrompt.instructionText
                    promptCopied = true
                } label: {
                    outlineLabel(
                        title: promptCopied ? "已复制" : "复制指令",
                        icon: promptCopied ? "checkmark" : "doc.on.doc"
                    )
                }

                Link(destination: ReportDeepSeekPastePrompt.deepSeekChatURL) {
                    outlineLabel(title: "打开网页", icon: "safari")
                }
            }
        }
        .padding(.top, 4)
    }

    // MARK: - Components

    private func sectionHeader(icon: String, title: String, subtitle: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(Theme.primaryDark)
                .frame(width: 28, alignment: .center)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(Theme.textPrimary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func importTextEditor(text: Binding<String>, minHeight: CGFloat, monospaced: Bool) -> some View {
        TextEditor(text: text)
            .frame(minHeight: minHeight)
            .padding(10)
            .background(inputBackground)
            .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadiusInput, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cornerRadiusInput, style: .continuous)
                    .stroke(Theme.primary.opacity(0.25), lineWidth: 1)
            )
            .font(monospaced ? .system(.caption, design: .monospaced) : .body)
            .scrollContentBackground(.hidden)
    }

    private var inputBackground: Color {
        colorScheme == .dark
            ? Theme.cardDark.opacity(0.6)
            : Color.white.opacity(0.85)
    }

    private func previewChip(_ text: String, detail: String?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(text, systemImage: "checkmark.circle.fill")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Theme.primaryDark)
            if let detail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Theme.primary.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadiusInput, style: .continuous))
    }

    private func errorLabel(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(Theme.warning)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func primaryButton(title: String, icon: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(enabled ? Theme.primary : Theme.primary.opacity(0.28))
                .foregroundStyle(enabled ? Theme.textPrimary : Theme.textSecondary)
                .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadiusButton, style: .continuous))
        }
        .disabled(!enabled)
    }

    private func outlineButton(title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            outlineLabel(title: title, icon: icon)
        }
        .disabled(isProcessing)
    }

    private func outlineLabel(title: String, icon: String) -> some View {
        Label(title, systemImage: icon)
            .font(.subheadline.weight(.medium))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(Theme.primary.opacity(0.12))
            .foregroundStyle(Theme.primaryDark)
            .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadiusButton, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cornerRadiusButton, style: .continuous)
                    .stroke(Theme.primary.opacity(0.35), lineWidth: 1)
            )
    }

    private func stepRow(number: Int, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.caption.bold())
                .foregroundStyle(Theme.textPrimary)
                .frame(width: 24, height: 24)
                .background(Theme.primary.opacity(0.35))
                .clipShape(Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
    }

    // MARK: - Preview helpers

    private var clinicPreviewText: String? {
        guard canParseClinicNote else { return nil }
        let extraction = ReportClinicNoteParser.parse(clinicNoteText)
        guard !extraction.isEmpty else { return nil }
        var parts: [String] = []
        if !extraction.metrics.isEmpty { parts.append("\(extraction.metrics.count) 项指标") }
        if !extraction.findings.isEmpty { parts.append("\(extraction.findings.count) 项结论") }
        parts.append("入库前自动对齐档案")
        return parts.joined(separator: " · ")
    }

    private var clinicPreviewExamDate: String? {
        guard canParseClinicNote,
              let date = ReportClinicNoteParser.parse(clinicNoteText).examDate else { return nil }
        return ReportDisplayFormatter.examDateLabel(date)
    }

    private var parsePreviewText: String? {
        guard canParseJSON, !isProcessing else { return nil }
        if pastedText.utf8.count > 16_384 {
            let kb = max(1, pastedText.utf8.count / 1024)
            return "大文件 \(kb) KB · 点「解析并进入校对」或选择 JSON 文件"
        }
        let extraction = ReportPasteParser.parse(pastedText)
        guard !extraction.isEmpty else { return nil }
        var parts: [String] = []
        if !extraction.metrics.isEmpty { parts.append("\(extraction.metrics.count) 项指标") }
        if !extraction.findings.isEmpty { parts.append("\(extraction.findings.count) 项异常发现") }
        if !extraction.recommendations.isEmpty { parts.append("\(extraction.recommendations.count) 条建议") }
        return parts.joined(separator: " · ")
    }

    private var parsePreviewExamDate: String? {
        guard canParseJSON, !isProcessing, pastedText.utf8.count <= 16_384,
              let date = ReportPasteParser.parse(pastedText).examDate else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy年M月d日"
        return formatter.string(from: date)
    }

    // MARK: - Actions

    @MainActor
    private func reportProgress(_ value: Double, _ message: String) {
        processingProgress = value
        processingStatus = message
    }

    @MainActor
    private func beginProcessing(_ message: String) {
        isProcessing = true
        processingProgress = 0.05
        processingStatus = message
    }

    @MainActor
    private func endProcessing() {
        isProcessing = false
        isImportingJSONFile = false
        processingProgress = 0
        processingStatus = "正在处理…"
    }

    private var importProgressHandler: ReportImportProgressHandler {
        { value, message in
            reportProgress(value, message)
        }
    }

    private func parseClinicNote() {
        clinicErrorMessage = nil
        beginProcessing("正在智能解析…")
        Task {
            defer { endProcessing() }
            do {
                verifyDraft = try await ReportClinicNoteImporter.importFromText(
                    clinicNoteText,
                    onProgress: importProgressHandler
                )
            } catch {
                clinicErrorMessage = error.localizedDescription
            }
        }
    }

    private func parsePaste() {
        errorMessage = nil
        beginProcessing("正在解析 JSON…")
        Task {
            defer { endProcessing() }
            do {
                let outcome = try await ReportPasteImporter.importFromPasteAsync(
                    pastedText,
                    onProgress: importProgressHandler
                )
                await applyPasteImportOutcome(outcome, sourceText: pastedText)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    @MainActor
    private func applyPasteImportOutcome(
        _ outcome: ReportPasteImporter.PasteImportOutcome,
        sourceText: String
    ) {
        switch outcome {
        case .single(let draft):
            if sourceText.utf8.count <= 32_768 {
                pastedText = sourceText
            } else {
                let kb = max(1, sourceText.utf8.count / 1024)
                pastedText = "已从文件导入约 \(kb) KB JSON（\(draft.metrics.count) 项指标 · \(draft.findings.count) 项结论）。原文过大未在文本框展开，结构化数据已完整解析。"
            }
            verifyDraft = draft
        case .staged(let payloads):
            pastedText = "检测到 \(payloads.count) 段报告，将逐段校对入库（与手动分段粘贴相同）。"
            stagedSession = StagedImportSession(payloads: payloads)
        }
    }

    private func importJSONFile(_ url: URL) async {
        errorMessage = nil
        await Task.yield()

        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }

        do {
            let fileName = url.lastPathComponent
            await reportProgress(0.08, "正在读取 \(fileName)…")

            let text = try await Task.detached(priority: .userInitiated) {
                try String(contentsOf: url, encoding: .utf8)
            }.value

            let sizeKB = max(1, text.utf8.count / 1024)
            await reportProgress(0.15, "已读取 \(sizeKB) KB，正在解析…")

            let outcome = try await ReportPasteImporter.importFromPasteAsync(
                text,
                onProgress: importProgressHandler
            )

            await reportProgress(0.99, "正在打开校对页…")
            await endProcessing()
            await Task.yield()
            await applyPasteImportOutcome(outcome, sourceText: text)
        } catch {
            errorMessage = error.localizedDescription
            await endProcessing()
        }
    }

    private func importPhoto(_ item: PhotosPickerItem) async {
        beginProcessing("正在读取图片…")
        errorMessage = nil
        clinicErrorMessage = nil
        defer { endProcessing() }

        do {
            guard let data = try await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data) else {
                clinicErrorMessage = "无法读取图片"
                return
            }
            let result = try await ReportImporter.importImage(
                image,
                fileName: "门诊截图.jpg",
                onProgress: importProgressHandler
            )
            verifyDraft = ReportClinicNoteImporter.alignOCRDraft(result)
        } catch {
            clinicErrorMessage = error.localizedDescription
        }
    }

    private func importPDF(_ url: URL) async {
        beginProcessing("正在读取 PDF…")
        clinicErrorMessage = nil
        defer { endProcessing() }

        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }

        do {
            let result = try await ReportImporter.importPDF(
                at: url,
                onProgress: importProgressHandler
            )
            verifyDraft = ReportClinicNoteImporter.alignOCRDraft(result)
        } catch {
            clinicErrorMessage = error.localizedDescription
        }
    }

    private func importCapturedImage(_ image: UIImage) async {
        beginProcessing("正在 OCR 识别…")
        clinicErrorMessage = nil
        defer {
            endProcessing()
            cameraImage = nil
        }

        do {
            let result = try await ReportImporter.importImage(
                image,
                fileName: "门诊拍照.jpg",
                onProgress: importProgressHandler
            )
            verifyDraft = ReportClinicNoteImporter.alignOCRDraft(result)
        } catch {
            clinicErrorMessage = error.localizedDescription
        }
    }
}

extension ReportImporter.ImportDraft: Hashable {
    static func == (lhs: ReportImporter.ImportDraft, rhs: ReportImporter.ImportDraft) -> Bool {
        lhs.fileName == rhs.fileName && lhs.rawText == rhs.rawText
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(fileName)
        hasher.combine(rawText)
    }
}

#Preview {
    ReportImportView()
}
