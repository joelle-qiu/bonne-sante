import SwiftUI
import PhotosUI
import SwiftData

/// 门诊预约截图导入 → 校对 → 待办 + 系统日历
/// @author jiali.qiu
struct ClinicAppointmentImportView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @State private var photoItem: PhotosPickerItem?
    @State private var draft: ClinicAppointmentImporter.Draft?
    @State private var pastedText = ""
    @State private var isProcessing = false
    @State private var processingStatus = "正在处理…"
    @State private var errorMessage: String?
    @State private var showingCamera = false
    @State private var cameraImage: UIImage?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                introCard
                photoActions
                pasteSection
                disclaimer
            }
            .padding(.horizontal, Theme.horizontalPadding)
            .padding(.vertical, 16)
        }
        .cycleThemedPageBackground()
        .navigationTitle("导入门诊预约")
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if isProcessing {
                ReportProcessingOverlay(message: processingStatus, progress: 0.5)
            }
        }
        .navigationDestination(item: $draft) { item in
            ClinicAppointmentVerifyView(draft: item) {
                dismiss()
            }
        }
        .onChange(of: photoItem) { _, newItem in
            guard let newItem else { return }
            Task { await importPhoto(newItem) }
        }
        .onChange(of: cameraImage) { _, image in
            guard let image else { return }
            Task { await importCaptured(image) }
        }
        .sheet(isPresented: $showingCamera) {
            CameraView(image: $cameraImage)
        }
        .alert("提示", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("好的", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var introCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("挂号 / 预约截图", systemImage: "calendar.badge.plus")
                .font(.headline)
            Text("识别科室、医院、就诊时间与主诉。OCR 在设备端完成；可选 DeepSeek 辅助结构化（不上传原图）。")
                .font(.caption)
                .foregroundStyle(Theme.adaptiveTextSecondary(colorScheme))
        }
        .morandiCard()
    }

    private var photoActions: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("拍照或选图")
                .font(.subheadline.weight(.semibold))
            HStack(spacing: 10) {
                Button {
                    showingCamera = true
                } label: {
                    Label("拍照", systemImage: "camera")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(MorandiQuickActionButtonStyle(variant: .secondary))

                PhotosPicker(selection: $photoItem, matching: .images) {
                    Label("相册", systemImage: "photo")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(MorandiQuickActionButtonStyle(variant: .secondary))
                .disabled(isProcessing)
            }
        }
        .morandiCard()
    }

    private var pasteSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("或粘贴预约文字")
                .font(.subheadline.weight(.semibold))
            TextEditor(text: $pastedText)
                .frame(minHeight: 100)
                .padding(8)
                .background(Theme.cardBackground(colorScheme))
                .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadiusCard))
            Button {
                Task { await importText() }
            } label: {
                Label("解析文字", systemImage: "text.insert")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(MorandiQuickActionButtonStyle(variant: .primary))
            .disabled(pastedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isProcessing)
        }
        .morandiCard()
    }

    private var disclaimer: some View {
        Text("预约信息仅供参考，请以医院官方通知为准。")
            .font(.caption2)
            .foregroundStyle(Theme.adaptiveTextSecondary(colorScheme))
            .multilineTextAlignment(.center)
    }

    private func importPhoto(_ item: PhotosPickerItem) async {
        isProcessing = true
        defer { isProcessing = false }
        do {
            guard let data = try await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data) else {
                errorMessage = "无法读取图片"
                return
            }
            processingStatus = "正在识别预约截图…"
            draft = try await ClinicAppointmentImporter.importFromImage(image)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func importCaptured(_ image: UIImage) async {
        isProcessing = true
        defer {
            isProcessing = false
            cameraImage = nil
        }
        do {
            processingStatus = "正在识别预约截图…"
            draft = try await ClinicAppointmentImporter.importFromImage(image)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func importText() async {
        isProcessing = true
        defer { isProcessing = false }
        do {
            processingStatus = "正在解析…"
            draft = try await ClinicAppointmentImporter.importFromText(pastedText)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Verify

struct ClinicAppointmentVerifyView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @State var draft: ClinicAppointmentImporter.Draft
    var onFinished: () -> Void

    @State private var hospital: String = ""
    @State private var department: String = ""
    @State private var appointmentDate = Date()
    @State private var chiefComplaint: String = ""
    @State private var location: String = ""
    @State private var doctorName: String = ""
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var savedTodo: TodoItem?

    var body: some View {
        Form {
            Section("识别结果（可编辑）") {
                TextField("医院", text: $hospital)
                TextField("科室", text: $department)
                DatePicker("就诊时间", selection: $appointmentDate)
                TextField("主诉 / 预约项目", text: $chiefComplaint)
                TextField("地点 / 院区", text: $location)
                TextField("医生（可选）", text: $doctorName)
            }

            if !draft.rawText.isEmpty {
                Section("OCR 原文") {
                    Text(draft.rawText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                if let savedTodo {
                    Label("已保存为待办", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(Theme.adaptiveAccent(colorScheme))
                    if savedTodo.calendarEventIdentifier.isEmpty {
                        Button {
                            Task { await addToCalendar(savedTodo) }
                        } label: {
                            Label("加入系统日历", systemImage: "calendar.badge.plus")
                        }
                        .disabled(isSaving)
                    } else {
                        Label("已加入系统日历", systemImage: "calendar")
                            .foregroundStyle(Theme.adaptiveTextSecondary(colorScheme))
                    }
                    Button("完成") {
                        onFinished()
                        dismiss()
                    }
                } else {
                    Button {
                        Task { await save(addToCalendar: false) }
                    } label: {
                        Label("保存为待办", systemImage: "tray.and.arrow.down")
                    }
                    .disabled(isSaving)

                    Button {
                        Task { await save(addToCalendar: true) }
                    } label: {
                        Label("保存并加入日历", systemImage: "calendar.badge.plus")
                    }
                    .disabled(isSaving)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .cycleThemedPageBackground()
        .navigationTitle("校对预约")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { bindDraft() }
        .alert("失败", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("好的", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func bindDraft() {
        hospital = draft.hospital
        department = draft.department
        appointmentDate = draft.appointmentDate
        chiefComplaint = draft.chiefComplaint
        location = draft.location
        doctorName = draft.doctorName
    }

    private func currentDraft() -> ClinicAppointmentImporter.Draft {
        ClinicAppointmentImporter.Draft(
            hospital: hospital.trimmingCharacters(in: .whitespacesAndNewlines),
            department: department.trimmingCharacters(in: .whitespacesAndNewlines),
            appointmentDate: appointmentDate,
            chiefComplaint: chiefComplaint.trimmingCharacters(in: .whitespacesAndNewlines),
            location: location.trimmingCharacters(in: .whitespacesAndNewlines),
            doctorName: doctorName.trimmingCharacters(in: .whitespacesAndNewlines),
            rawText: draft.rawText
        )
    }

    private func save(addToCalendar: Bool) async {
        isSaving = true
        defer { isSaving = false }

        let finalDraft = currentDraft()
        let todo = ClinicAppointmentImporter.makeTodo(from: finalDraft)
        modelContext.insert(todo)

        if addToCalendar {
            do {
                let eventID = try await CalendarService.addAppointment(for: todo)
                todo.calendarEventIdentifier = eventID
            } catch {
                errorMessage = error.localizedDescription
            }
        }

        TodoService.scheduleReminders(for: todo)
        try? modelContext.save()
        savedTodo = todo
    }

    private func addToCalendar(_ todo: TodoItem) async {
        isSaving = true
        defer { isSaving = false }
        do {
            let eventID = try await CalendarService.addAppointment(for: todo)
            todo.calendarEventIdentifier = eventID
            try? modelContext.save()
            savedTodo = todo
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

extension ClinicAppointmentImporter.Draft: Hashable {
    static func == (lhs: ClinicAppointmentImporter.Draft, rhs: ClinicAppointmentImporter.Draft) -> Bool {
        lhs.rawText == rhs.rawText && lhs.appointmentDate == rhs.appointmentDate
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(rawText)
        hasher.combine(appointmentDate)
    }
}

#Preview {
    NavigationStack {
        ClinicAppointmentImportView()
    }
    .modelContainer(for: TodoItem.self, inMemory: true)
}
