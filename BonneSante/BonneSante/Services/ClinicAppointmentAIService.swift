import Foundation

/// DeepSeek 结构化门诊预约 OCR 文本（不上传原图）
/// @author jiali.qiu
enum ClinicAppointmentAIService {

    private struct AIResponse: Decodable {
        let hospital: String?
        let department: String?
        let appointmentDateISO: String?
        let chiefComplaint: String?
        let location: String?
        let doctorName: String?
    }

    private static let systemPrompt = """
你是医疗预约信息提取助手。从 OCR 文本中提取门诊预约字段，仅返回 JSON：
{
  "hospital": "XX医院",
  "department": "妇科",
  "appointmentDateISO": "2026-06-25T09:30:00",
  "chiefComplaint": "复查",
  "location": "东院区 3 楼",
  "doctorName": "张医生"
}
缺失字段用空字符串；时间尽量解析为 ISO8601；禁止 markdown。
"""

    static func enrich(_ draft: ClinicAppointmentParser.Draft) async throws -> ClinicAppointmentParser.Draft {
        guard APIKeyManager.isDeepSeekConfigured,
              let apiKey = APIKeyManager.deepSeekAPIKey else {
            return draft
        }

        let sanitized = ReportAIService.sanitizeForCloud(draft.rawText)
        guard !sanitized.isEmpty else { return draft }

        let user = "OCR 文本：\n\(sanitized.prefix(4000))"
        let content = try await requestJSON(system: systemPrompt, user: user, apiKey: apiKey)
        return merge(draft, json: content)
    }

    private static func merge(_ draft: ClinicAppointmentParser.Draft, json: String) -> ClinicAppointmentParser.Draft {
        guard let data = extractJSONObject(from: json).data(using: .utf8),
              let decoded = try? JSONDecoder().decode(AIResponse.self, from: data) else {
            return draft
        }

        var result = draft
        if let hospital = decoded.hospital?.trimmingCharacters(in: .whitespacesAndNewlines), !hospital.isEmpty {
            result.hospital = hospital
        }
        if let department = decoded.department?.trimmingCharacters(in: .whitespacesAndNewlines), !department.isEmpty {
            result.department = department
        }
        if let complaint = decoded.chiefComplaint?.trimmingCharacters(in: .whitespacesAndNewlines), !complaint.isEmpty {
            result.chiefComplaint = complaint
        }
        if let location = decoded.location?.trimmingCharacters(in: .whitespacesAndNewlines), !location.isEmpty {
            result.location = location
        }
        if let doctor = decoded.doctorName?.trimmingCharacters(in: .whitespacesAndNewlines), !doctor.isEmpty {
            result.doctorName = doctor
        }
        if let iso = decoded.appointmentDateISO,
           let date = ISO8601DateFormatter().date(from: iso)
            ?? parseFlexibleDate(iso) {
            result.appointmentDate = date
        }
        return result
    }

    private static func parseFlexibleDate(_ text: String) -> Date? {
        let formats = [
            "yyyy-MM-dd'T'HH:mm:ss",
            "yyyy-MM-dd HH:mm",
            "yyyy/MM/dd HH:mm"
        ]
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        for format in formats {
            formatter.dateFormat = format
            if let date = formatter.date(from: text) { return date }
        }
        return nil
    }

    private static func requestJSON(system: String, user: String, apiKey: String) async throws -> String {
        var request = URLRequest(url: APIKeyManager.deepSeekEndpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 45

        let body: [String: Any] = [
            "model": APIKeyManager.deepSeekModel,
            "messages": [
                ["role": "system", "content": system],
                ["role": "user", "content": user]
            ],
            "temperature": 0.2,
            "max_tokens": 800
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw AIServiceError.parsingError("DeepSeek 请求失败")
        }

        struct ChatResponse: Decodable {
            struct Choice: Decodable {
                struct Message: Decodable { let content: String? }
                let message: Message?
            }
            let choices: [Choice]?
        }

        let decoded = try JSONDecoder().decode(ChatResponse.self, from: data)
        guard let content = decoded.choices?.first?.message?.content else {
            throw AIServiceError.parsingError("DeepSeek 返回为空")
        }
        return content
    }

    private static func extractJSONObject(from text: String) -> String {
        if let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}") {
            return String(text[start...end])
        }
        return text
    }
}
