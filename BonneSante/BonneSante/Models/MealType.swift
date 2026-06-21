import Foundation

/// 饮食餐次
/// @author jiali.qiu
enum MealType: String, CaseIterable, Codable, Identifiable {
    case breakfast
    case lunch
    case afternoonTea = "afternoon_tea"
    case dinner
    case lateNight = "late_night"
    case snack

    var id: String { rawValue }

    var label: String {
        switch self {
        case .breakfast: return "早餐"
        case .lunch: return "午餐"
        case .afternoonTea: return "下午茶"
        case .dinner: return "晚餐"
        case .lateNight: return "夜宵"
        case .snack: return "加餐"
        }
    }

    var icon: String {
        switch self {
        case .breakfast: return "sunrise.fill"
        case .lunch: return "sun.max.fill"
        case .afternoonTea: return "cup.and.saucer.fill"
        case .dinner: return "moon.stars.fill"
        case .lateNight: return "moon.fill"
        case .snack: return "carrot.fill"
        }
    }

    /// 按当前时间推断默认餐次
    static func inferredFromCurrentTime(_ date: Date = Date()) -> MealType {
        inferredFromTime(date)
    }

    static func inferredFromTime(_ date: Date) -> MealType {
        let hour = Calendar.current.component(.hour, from: date)
        switch hour {
        case 5..<10: return .breakfast
        case 10..<14: return .lunch
        case 14..<17: return .afternoonTea
        case 17..<21: return .dinner
        default: return .lateNight
        }
    }

    /// 从用户文字中识别餐次关键词
    static func inferredFromText(_ text: String) -> MealType? {
        let normalized = text.lowercased()
        let rules: [(MealType, [String])] = [
            (.breakfast, ["早餐", "早饭", "早飯", "breakfast", "早上吃", "清晨"]),
            (.lunch, ["午餐", "午饭", "中饭", "午餐吃", "lunch", "中午吃", "午间"]),
            (.afternoonTea, ["下午茶", "午后茶", "afternoon tea", "茶点", "下午吃"]),
            (.dinner, ["晚餐", "晚饭", "dinner", "晚上吃", "晚间"]),
            (.lateNight, ["夜宵", "宵夜", "深夜", "late night", "半夜", "凌晨吃"]),
            (.snack, ["加餐", "零食", "snack", "点心"])
        ]
        for (meal, keywords) in rules {
            if keywords.contains(where: { normalized.contains($0.lowercased()) }) {
                return meal
            }
        }
        return nil
    }

    /// 解析 AI 返回的 meal_type 字段
    static func fromAIValue(_ value: String?) -> MealType? {
        guard let value, !value.isEmpty else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let direct = MealType(rawValue: trimmed) { return direct }
        switch trimmed {
        case "breakfast", "早餐", "早饭": return .breakfast
        case "lunch", "午餐", "午饭", "中饭": return .lunch
        case "afternoon_tea", "afternoon tea", "下午茶", "茶点": return .afternoonTea
        case "dinner", "晚餐", "晚饭": return .dinner
        case "late_night", "late night", "夜宵", "宵夜": return .lateNight
        case "snack", "加餐", "零食": return .snack
        default: return nil
        }
    }
}
