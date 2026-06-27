import Foundation

/// AI 教练对话指令与今日计划草案解析
/// @author jiali.qiu

/// 用户发给 AI 教练的显式指令
enum WorkoutCoachCommand: Equatable {
    case importTodayPlan
    case chat(String)

    private static let importTriggers = [
        "导入今日训练计划",
        "导入训练计划",
        "应用训练计划",
        "更新今日计划",
        "导入计划",
        "写入训练计划",
        "更新动作清单"
    ]

    static func parse(_ input: String) -> WorkoutCoachCommand {
        let normalized = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return .chat("") }
        if importTriggers.contains(where: { normalized.contains($0) }) {
            return .importTodayPlan
        }
        return .chat(normalized)
    }
}

/// 教练输出的单场训练计划（可写入 SwiftData）
struct CoachSessionPlan: Equatable {
    var workoutType: String?
    var sessionTargetMinutes: Int
    var sessionTargetCalories: Double
    var replanNote: String
    var exercises: [WorkoutPlanEngine.PlannedExercise]

    var exerciseCount: Int { exercises.count }
}

enum WorkoutCoachPlanParser {

    static let draftStart = "<!--plan-draft-->"
    static let draftEnd = "<!--/plan-draft-->"

    /// 分离用户可见文案与隐藏 JSON 草案
    static func splitDisplayAndDraft(_ text: String) -> (display: String, draftJSON: String?) {
        guard let startRange = text.range(of: draftStart),
              let endRange = text.range(of: draftEnd),
              startRange.lowerBound < endRange.lowerBound else {
            return (text.trimmingCharacters(in: .whitespacesAndNewlines), nil)
        }
        let json = String(text[startRange.upperBound..<endRange.lowerBound])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        var display = text
        display.removeSubrange(startRange.lowerBound..<endRange.upperBound)
        return (display.trimmingCharacters(in: .whitespacesAndNewlines), json.isEmpty ? nil : json)
    }

    /// 从最近助手回复中提取 plan-draft
    static func latestDraftJSON(from messages: [(role: String, content: String)]) -> String? {
        for msg in messages.reversed() where msg.role == "assistant" {
            let (_, draft) = splitDisplayAndDraft(msg.content)
            if let draft { return draft }
        }
        return nil
    }

    static func parseSessionPlan(from jsonText: String) throws -> CoachSessionPlan {
        let extracted = extractJSONObject(from: jsonText)
        guard let data = extracted.data(using: .utf8) else {
            throw AIServiceError.parsingError("计划 JSON 无效")
        }

        struct Payload: Decodable {
            let workoutType: String?
            let sessionTargetMinutes: Int?
            let sessionTargetCalories: Double?
            let replanNote: String?
            let exercises: [WorkoutPlanAIService.ExerciseJSON]?
        }

        let decoded = try JSONDecoder().decode(Payload.self, from: data)
        let exercises = (decoded.exercises ?? []).compactMap(WorkoutPlanAIService.parseExercisePublic)
        guard !exercises.isEmpty else {
            throw AIServiceError.parsingError("计划中未包含有效动作")
        }

        let calories = decoded.sessionTargetCalories
            ?? exercises.reduce(0) { $0 + $1.targetCalories }
        let minutes = max(decoded.sessionTargetMinutes ?? 45, 10)

        return CoachSessionPlan(
            workoutType: decoded.workoutType?.trimmingCharacters(in: .whitespacesAndNewlines),
            sessionTargetMinutes: minutes,
            sessionTargetCalories: max(calories, 50),
            replanNote: decoded.replanNote?.trimmingCharacters(in: .whitespacesAndNewlines)
                ?? "AI 教练已根据对话更新今日动作清单。",
            exercises: exercises
        )
    }

    private static func extractJSONObject(from text: String) -> String {
        if let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}") {
            return String(text[start...end])
        }
        return text
    }
}
