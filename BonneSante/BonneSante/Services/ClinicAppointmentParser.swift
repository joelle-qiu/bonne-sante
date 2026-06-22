import Foundation

/// 门诊预约截图 OCR 文本本地解析（科室 / 医院 / 时间 / 主诉）
/// @author jiali.qiu
enum ClinicAppointmentParser {

    struct Draft: Equatable {
        var hospital: String
        var department: String
        var appointmentDate: Date
        var chiefComplaint: String
        var location: String
        var doctorName: String
        var rawText: String

        var isEmpty: Bool {
            hospital.isEmpty && department.isEmpty && chiefComplaint.isEmpty
        }

        var displayTitle: String {
            if !department.isEmpty, !hospital.isEmpty {
                return "\(department) · \(hospital)"
            }
            if !department.isEmpty { return department }
            if !hospital.isEmpty { return hospital }
            return "门诊预约"
        }
    }

    static func parse(_ rawText: String) -> Draft {
        let lines = rawText
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let joined = lines.joined(separator: "\n")
        return Draft(
            hospital: extractHospital(from: lines, fullText: joined),
            department: extractDepartment(from: lines, fullText: joined),
            appointmentDate: extractDate(from: joined) ?? defaultAppointmentDate(),
            chiefComplaint: extractChiefComplaint(from: lines, fullText: joined),
            location: extractLocation(from: lines, fullText: joined),
            doctorName: extractDoctor(from: lines, fullText: joined),
            rawText: rawText
        )
    }

    // MARK: - Extractors

    private static func extractHospital(from lines: [String], fullText: String) -> String {
        let patterns = [
            #"([\u4e00-\u9fffA-Za-z0-9（）()·\-]{2,30}(?:医院|医疗中心|保健院|卫生院))"#,
            #"(?:医院|就诊医院)[:：]\s*([^\n]{2,40})"#
        ]
        for pattern in patterns {
            if let match = firstCapture(in: fullText, pattern: pattern) {
                return clean(match)
            }
        }
        for line in lines where line.contains("医院") || line.contains("医疗中心") {
            return clean(line)
        }
        return ""
    }

    private static func extractDepartment(from lines: [String], fullText: String) -> String {
        let patterns = [
            #"(?:科室|就诊科室|挂号科室)[:：]\s*([^\n]{2,20})"#,
            #"([\u4e00-\u9fff]{2,12}(?:科|门诊))"#
        ]
        for pattern in patterns {
            if let match = firstCapture(in: fullText, pattern: pattern) {
                let value = clean(match)
                if !value.contains("医院") { return value }
            }
        }
        return ""
    }

    private static func extractChiefComplaint(from lines: [String], fullText: String) -> String {
        let patterns = [
            #"(?:主诉|就诊原因|病情描述|症状)[:：]\s*([^\n]{2,80})"#,
            #"(?:预约项目|挂号类型)[:：]\s*([^\n]{2,40})"#
        ]
        for pattern in patterns {
            if let match = firstCapture(in: fullText, pattern: pattern) {
                return clean(match)
            }
        }
        for line in lines where line.contains("复查") || line.contains("随访") {
            return clean(line)
        }
        return ""
    }

    private static func extractLocation(from lines: [String], fullText: String) -> String {
        let patterns = [
            #"(?:地点|地址|院区|就诊地点)[:：]\s*([^\n]{4,60})"#,
            #"([\u4e00-\u9fff]{2,8}院区)"#
        ]
        for pattern in patterns {
            if let match = firstCapture(in: fullText, pattern: pattern) {
                return clean(match)
            }
        }
        return ""
    }

    private static func extractDoctor(from lines: [String], fullText: String) -> String {
        let patterns = [
            #"(?:医生|医师|专家)[:：]\s*([^\n]{2,12})"#,
            #"([\u4e00-\u9fff]{1,4}医生)"#
        ]
        for pattern in patterns {
            if let match = firstCapture(in: fullText, pattern: pattern) {
                return clean(match)
            }
        }
        return ""
    }

    private static func extractDate(from text: String) -> Date? {
        let patterns: [(String, String)] = [
            (#"(\d{4})[年\-/.](\d{1,2})[月\-/.](\d{1,2})[日号]?\s*(\d{1,2})[:：](\d{2})"#, "ymdhm"),
            (#"(\d{4})-(\d{2})-(\d{2})\s+(\d{1,2}):(\d{2})"#, "ymdhm"),
            (#"(\d{1,2})[月\-/.](\d{1,2})[日号]?\s*(\d{1,2})[:：](\d{2})"#, "mdhm"),
            (#"(\d{4})[年\-/.](\d{1,2})[月\-/.](\d{1,2})[日号]?"#, "ymd")
        ]

        for (pattern, kind) in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else {
                continue
            }
            func int(at index: Int) -> Int? {
                guard let range = Range(match.range(at: index), in: text) else { return nil }
                return Int(text[range])
            }
            let calendar = Calendar.current
            let now = Date()
            var components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: now)

            switch kind {
            case "ymdhm":
                guard let y = int(at: 1), let m = int(at: 2), let d = int(at: 3),
                      let h = int(at: 4), let min = int(at: 5) else { continue }
                components.year = y; components.month = m; components.day = d
                components.hour = h; components.minute = min
            case "mdhm":
                guard let m = int(at: 1), let d = int(at: 2),
                      let h = int(at: 3), let min = int(at: 4) else { continue }
                components.month = m; components.day = d
                components.hour = h; components.minute = min
            case "ymd":
                guard let y = int(at: 1), let m = int(at: 2), let d = int(at: 3) else { continue }
                components.year = y; components.month = m; components.day = d
                components.hour = 9; components.minute = 0
            default:
                continue
            }
            if let date = calendar.date(from: components) { return date }
        }

        for line in ["预约时间", "就诊时间", "挂号时间", "到院时间"] {
            if let range = text.range(of: line) {
                let tail = String(text[range.upperBound...]).prefix(40)
                if let date = extractDate(from: String(tail)) { return date }
            }
        }
        return nil
    }

    private static func defaultAppointmentDate() -> Date {
        Calendar.current.date(byAdding: .day, value: 1, to: Date())
            ?? Date().addingTimeInterval(86400)
    }

    private static func firstCapture(in text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[range])
    }

    private static func clean(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "  ", with: " ")
    }
}
