import Foundation
import UIKit

/// 门诊预约截图导入：Vision OCR + 本地解析 + 可选 DeepSeek
/// @author jiali.qiu
enum ClinicAppointmentImporter {

    typealias Draft = ClinicAppointmentParser.Draft

    static func importFromImage(
        _ image: UIImage,
        useAI: Bool = true,
        onProgress: ReportImportProgressHandler? = nil
    ) async throws -> Draft {
        await ReportImportProgressReporter.emit(onProgress, 0.15, "正在 OCR 识别…")
        let rawText = try await ReportImporter.recognizePlainText(in: image)

        await ReportImportProgressReporter.emit(onProgress, 0.45, "正在解析预约信息…")
        var draft = ClinicAppointmentParser.parse(rawText)

        if useAI, APIKeyManager.isDeepSeekConfigured {
            await ReportImportProgressReporter.emit(onProgress, 0.7, "DeepSeek 结构化…")
            draft = try await ClinicAppointmentAIService.enrich(draft)
        }

        await ReportImportProgressReporter.emit(onProgress, 0.95, "完成")
        return draft
    }

    static func importFromText(_ text: String, useAI: Bool = true) async throws -> Draft {
        var draft = ClinicAppointmentParser.parse(text)
        if useAI, APIKeyManager.isDeepSeekConfigured {
            draft = try await ClinicAppointmentAIService.enrich(draft)
        }
        return draft
    }

    static func makeTodo(from draft: Draft) -> TodoItem {
        var notesParts: [String] = []
        if !draft.chiefComplaint.isEmpty { notesParts.append("主诉：\(draft.chiefComplaint)") }
        if !draft.doctorName.isEmpty { notesParts.append("医生：\(draft.doctorName)") }
        notesParts.append("以上内容仅供参考，请遵医嘱。")

        return TodoItem(
            title: draft.displayTitle,
            dueDate: draft.appointmentDate,
            location: draft.location.isEmpty ? draft.hospital : draft.location,
            notes: notesParts.joined(separator: "\n"),
            source: .appointment,
            department: draft.department
        )
    }
}
