import Foundation

/// DeepSeek 训练计划、换动作重评估、AI 教练
/// @author jiali.qiu
enum WorkoutPlanAIService {

    struct AIResponse: Decodable {
        let weeklySummary: String?
        let weeklyBurnGoalKcal: Double?
        let dietAdvice: String?
        let dailyNutrition: DailyNutritionJSON?
        let trainingDayNutrition: DailyNutritionJSON?
        let restDayNutrition: DailyNutritionJSON?
        let weeklyModerateMinutesGoal: Int?
        let strengthSessionsGoal: Int?
        let sessions: [SessionJSON]?
    }

    struct DailyNutritionJSON: Decodable {
        let caloriesKcal: Double?
        let proteinGrams: Double?
        let carbGrams: Double?
        let fatGrams: Double?
        let notes: String?
    }

    struct SessionJSON: Decodable {
        let dayOfWeek: Int?
        let workoutType: String?
        let targetMinutes: Int?
        let targetCalories: Double?
        let intensity: String?
        let notes: String?
        let moodReminder: String?
        let exercises: [ExerciseJSON]?
    }

    struct ExerciseJSON: Decodable {
        let name: String?
        let muscleGroup: String?
        let equipment: String?
        let sets: Int?
        let reps: String?
        let restSeconds: Int?
        let targetCalories: Double?
        let exerciseKind: String?
        let notes: String?
    }

    struct SwapResponse: Decodable {
        let alternatives: [ExerciseJSON]?
        let replacement: ExerciseJSON?
        let sessionTargetCalories: Double?
        let sessionTargetMinutes: Int?
        let replanNote: String?
        let addToExcludedList: Bool?
    }

    struct SwapCandidatesResult {
        var alternatives: [WorkoutPlanEngine.PlannedExercise]
        var sessionTargetCalories: Double
        var sessionTargetMinutes: Int
        var replanNote: String
        var addToExcludedList: Bool
    }

    struct SwapResult {
        var replacement: WorkoutPlanEngine.PlannedExercise
        var sessionTargetCalories: Double
        var sessionTargetMinutes: Int
        var replanNote: String
        var addToExcludedList: Bool
    }

    static func generatePlan(
        context: String,
        weeklySessions: Int,
        planType: WorkoutPlanType = .balanced,
        planStyle: WorkoutPlanStyle = .professional,
        excluded: [String] = [],
        fallbackBudget: Double? = nil,
        fallbackProtein: Double? = nil
    ) async throws -> WorkoutPlanEngine.Output {
        let content = try await requestJSON(
            system: WorkoutPlanPrompt.systemPrompt(for: planType, style: planStyle),
            user: WorkoutPlanPrompt.userPrompt(
                context: context,
                weeklySessions: weeklySessions,
                planType: planType,
                planStyle: planStyle,
                excluded: excluded
            ),
            temperature: planStyle == .moodWeather ? 0.78 : 0.35
        )
        return try parseOutput(
            from: content,
            expectedSessions: weeklySessions,
            fallbackBudget: fallbackBudget,
            fallbackProtein: fallbackProtein
        )
    }

    static func fetchSwapCandidates(
        sessionSummary: String,
        exerciseName: String,
        reason: String,
        excluded: [String]
    ) async throws -> SwapCandidatesResult {
        let content = try await requestJSON(
            system: WorkoutPlanPrompt.swapSystemPrompt,
            user: WorkoutPlanPrompt.swapUserPrompt(
                sessionSummary: sessionSummary,
                exerciseName: exerciseName,
                reason: reason,
                excluded: excluded
            )
        )
        return try parseSwapCandidates(from: content)
    }

    /// 兼容旧接口
    static func swapExercise(
        sessionSummary: String,
        exerciseName: String,
        reason: String,
        excluded: [String]
    ) async throws -> SwapResult {
        let candidates = try await fetchSwapCandidates(
            sessionSummary: sessionSummary,
            exerciseName: exerciseName,
            reason: reason,
            excluded: excluded
        )
        guard let first = candidates.alternatives.first else {
            throw AIServiceError.parsingError("未返回有效替代动作")
        }
        return SwapResult(
            replacement: first,
            sessionTargetCalories: candidates.sessionTargetCalories,
            sessionTargetMinutes: candidates.sessionTargetMinutes,
            replanNote: candidates.replanNote,
            addToExcludedList: candidates.addToExcludedList
        )
    }

    static func coachReply(
        sessionContext: String,
        question: String,
        history: [(role: String, content: String)] = [],
        genderLabel: String? = nil,
        healthProfile: String? = nil
    ) async throws -> String {
        guard APIKeyManager.isDeepSeekConfigured, let apiKey = APIKeyManager.deepSeekAPIKey else {
            throw AIServiceError.apiKeyNotConfigured
        }

        let user = WorkoutPlanPrompt.coachUserPrompt(
            sessionContext: sessionContext,
            question: question,
            genderLabel: genderLabel,
            healthProfile: healthProfile
        )

        var apiMessages: [[String: String]] = [
            ["role": "system", "content": WorkoutPlanPrompt.coachSystemPrompt]
        ]
        for item in history.suffix(ChatMessageChannel.maxContextMessages) where !item.content.isEmpty {
            apiMessages.append(["role": item.role, "content": item.content])
        }
        apiMessages.append(["role": "user", "content": user])

        let body: [String: Any] = [
            "model": APIKeyManager.deepSeekModel,
            "messages": apiMessages,
            "temperature": 0.5
        ]

        var request = URLRequest(url: APIKeyManager.deepSeekEndpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 45

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw AIServiceError.parsingError("AI 教练请求失败")
        }

        struct Envelope: Decodable {
            struct Choice: Decodable {
                struct Message: Decodable { let content: String }
                let message: Message
            }
            let choices: [Choice]?
        }

        let envelope = try JSONDecoder().decode(Envelope.self, from: data)
        guard let text = envelope.choices?.first?.message.content.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else {
            throw AIServiceError.parsingError("AI 教练返回为空")
        }
        return text
    }

    /// 从对话合成并解析今日计划（导入指令且无本地草案时）
    static func synthesizeSessionPlanFromConversation(
        sessionContext: String,
        history: [(role: String, content: String)],
        latestUserMessage: String,
        genderLabel: String? = nil
    ) async throws -> CoachSessionPlan {
        guard APIKeyManager.isDeepSeekConfigured, let apiKey = APIKeyManager.deepSeekAPIKey else {
            throw AIServiceError.apiKeyNotConfigured
        }

        let summary = WorkoutPlanPrompt.conversationSummaryForImport(
            history: history,
            latestUserMessage: latestUserMessage
        )
        let user = WorkoutPlanPrompt.coachImportUserPrompt(
            sessionContext: sessionContext,
            conversationSummary: summary,
            genderLabel: genderLabel
        )

        let body: [String: Any] = [
            "model": APIKeyManager.deepSeekModel,
            "messages": [
                ["role": "system", "content": WorkoutPlanPrompt.coachImportSystemPrompt],
                ["role": "user", "content": user]
            ],
            "temperature": 0.35
        ]

        var request = URLRequest(url: APIKeyManager.deepSeekEndpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 60

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw AIServiceError.parsingError("生成训练计划失败")
        }

        struct Envelope: Decodable {
            struct Choice: Decodable {
                struct Message: Decodable { let content: String }
                let message: Message
            }
            let choices: [Choice]?
        }

        let envelope = try JSONDecoder().decode(Envelope.self, from: data)
        guard let raw = envelope.choices?.first?.message.content.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty else {
            throw AIServiceError.parsingError("AI 未返回训练计划")
        }
        return try WorkoutCoachPlanParser.parseSessionPlan(from: raw)
    }

    /// 供 WorkoutCoachPlanParser 解析动作 JSON
    static func parseExercisePublic(_ item: ExerciseJSON) -> WorkoutPlanEngine.PlannedExercise? {
        parseExercise(item)
    }

    // MARK: - Private

    private static func requestJSON(system: String, user: String, temperature: Double = 0.35) async throws -> String {
        guard APIKeyManager.isDeepSeekConfigured, let apiKey = APIKeyManager.deepSeekAPIKey else {
            throw AIServiceError.apiKeyNotConfigured
        }

        let body: [String: Any] = [
            "model": APIKeyManager.deepSeekModel,
            "messages": [
                ["role": "system", "content": system],
                ["role": "user", "content": user]
            ],
            "response_format": ["type": "json_object"],
            "temperature": temperature
        ]

        var request = URLRequest(url: APIKeyManager.deepSeekEndpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 60

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let raw = String(data: data, encoding: .utf8) ?? ""
            throw AIServiceError.parsingError("AI 请求失败：\(raw.prefix(200))")
        }

        struct APIEnvelope: Decodable {
            struct Choice: Decodable {
                struct Message: Decodable { let content: String }
                let message: Message
            }
            let choices: [Choice]?
        }

        let envelope = try JSONDecoder().decode(APIEnvelope.self, from: data)
        guard let content = envelope.choices?.first?.message.content else {
            throw AIServiceError.parsingError("AI 返回为空")
        }
        return content
    }

    private static func parseOutput(
        from content: String,
        expectedSessions: Int,
        fallbackBudget: Double? = nil,
        fallbackProtein: Double? = nil
    ) throws -> WorkoutPlanEngine.Output {
        let json = extractJSONObject(from: content)
        guard let data = json.data(using: .utf8) else {
            throw AIServiceError.parsingError("无法解析 AI 响应")
        }

        let decoded = try JSONDecoder().decode(AIResponse.self, from: data)
        let sessions = (decoded.sessions ?? []).compactMap { item -> WorkoutPlanEngine.PlannedSession? in
            guard let day = item.dayOfWeek, (1...7).contains(day),
                  let type = item.workoutType?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !type.isEmpty else { return nil }
            let minutes = max(item.targetMinutes ?? 30, 10)
            let intensity = normalizeIntensity(item.intensity)
            let exercises = (item.exercises ?? []).compactMap(parseExercise)
            let calFromExercises = exercises.reduce(0) { $0 + $1.targetCalories }
            let targetCal = item.targetCalories ?? calFromExercises
            let moodReminder = resolvedMoodReminder(from: item, workoutType: type)
            return WorkoutPlanEngine.PlannedSession(
                dayOfWeek: day,
                workoutType: type,
                targetMinutes: minutes,
                intensity: intensity,
                notes: item.notes?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                moodReminder: moodReminder,
                targetCalories: targetCal > 0 ? targetCal : WorkoutPlanEngine.estimatedSessionCaloriesPublic(minutes: minutes, intensity: intensity),
                exercises: exercises
            )
        }

        guard !sessions.isEmpty else {
            throw AIServiceError.parsingError("AI 未返回有效训练条目")
        }

        let trimmed = Array(sessions.prefix(expectedSessions))
        let diet = decoded.dietAdvice?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let summary = decoded.weeklySummary?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let weeklyBurn = decoded.weeklyBurnGoalKcal ?? trimmed.reduce(0) { $0 + $1.targetCalories }

        let splitNutrition = parseSplitNutrition(
            training: decoded.trainingDayNutrition ?? decoded.dailyNutrition,
            rest: decoded.restDayNutrition,
            fallbackBudget: fallbackBudget,
            fallbackProtein: fallbackProtein
        )

        return WorkoutPlanEngine.Output(
            sessions: trimmed,
            weeklyModerateMinutesGoal: decoded.weeklyModerateMinutesGoal ?? 120,
            strengthSessionsGoal: decoded.strengthSessionsGoal ?? 1,
            dietAdvice: diet.isEmpty ? "请按训练日/休息日营养目标安排摄入。" : diet,
            weeklySummary: summary.isEmpty ? "AI 定制周训练计划" : summary,
            weeklyBurnGoalKcal: weeklyBurn,
            splitNutrition: splitNutrition
        )
    }

    private static func parseSplitNutrition(
        training: DailyNutritionJSON?,
        rest: DailyNutritionJSON?,
        fallbackBudget: Double?,
        fallbackProtein: Double?
    ) -> WorkoutNutritionPlanner.SplitNutritionPlan {
        let fallbackSplit = WorkoutNutritionPlanner.fromEngineSplit(
            dailyBudget: fallbackBudget,
            proteinGrams: fallbackProtein,
            carbGrams: nil,
            fatGrams: nil,
            phase: .unknown
        )
        let trainingPlan = parseDailyNutritionJSON(
            training,
            fallback: fallbackSplit.trainingDay
        )
        let restPlan: WorkoutNutritionPlanner.DailyNutritionPlan
        if let rest {
            restPlan = parseDailyNutritionJSON(rest, fallback: fallbackSplit.restDay)
        } else {
            restPlan = WorkoutNutritionPlanner.deriveRestDayFromTraining(trainingPlan)
        }
        return WorkoutNutritionPlanner.SplitNutritionPlan(
            trainingDay: trainingPlan,
            restDay: restPlan
        )
    }

    private static func parseDailyNutritionJSON(
        _ json: DailyNutritionJSON?,
        fallback: WorkoutNutritionPlanner.DailyNutritionPlan
    ) -> WorkoutNutritionPlanner.DailyNutritionPlan {
        guard let json else { return fallback }
        let cal = json.caloriesKcal ?? fallback.caloriesKcal
        let protein = json.proteinGrams ?? fallback.proteinGrams
        let fat = json.fatGrams ?? fallback.fatGrams
        var carbs = json.carbGrams ?? 0
        if carbs <= 0 {
            carbs = max((cal - protein * 4 - fat * 9) / 4, 65)
        }
        return WorkoutNutritionPlanner.DailyNutritionPlan(
            caloriesKcal: cal,
            proteinGrams: protein,
            carbGrams: carbs,
            fatGrams: fat,
            notes: json.notes?.trimmingCharacters(in: .whitespacesAndNewlines) ?? fallback.notes
        )
    }

    private static func parseDailyNutrition(
        _ json: DailyNutritionJSON?,
        fallbackBudget: Double?,
        fallbackProtein: Double?
    ) -> WorkoutNutritionPlanner.DailyNutritionPlan {
        let split = parseSplitNutrition(
            training: json,
            rest: nil,
            fallbackBudget: fallbackBudget,
            fallbackProtein: fallbackProtein
        )
        return split.trainingDay
    }

    private static func parseSwapCandidates(from content: String) throws -> SwapCandidatesResult {
        let json = extractJSONObject(from: content)
        guard let data = json.data(using: .utf8) else {
            throw AIServiceError.parsingError("无法解析换动作响应")
        }
        let decoded = try JSONDecoder().decode(SwapResponse.self, from: data)
        var alternatives = (decoded.alternatives ?? []).compactMap(parseExercise)
        if alternatives.isEmpty, let single = decoded.replacement.flatMap(parseExercise) {
            alternatives = [single]
        }
        guard !alternatives.isEmpty else {
            throw AIServiceError.parsingError("未返回有效替代动作")
        }
        return SwapCandidatesResult(
            alternatives: Array(alternatives.prefix(3)),
            sessionTargetCalories: decoded.sessionTargetCalories ?? alternatives[0].targetCalories,
            sessionTargetMinutes: decoded.sessionTargetMinutes ?? 45,
            replanNote: decoded.replanNote?.trimmingCharacters(in: .whitespacesAndNewlines)
                ?? "已更换动作，本场消耗目标已重新评估。",
            addToExcludedList: decoded.addToExcludedList ?? false
        )
    }

    private static func parseSwap(from content: String) throws -> SwapResult {
        let candidates = try parseSwapCandidates(from: content)
        guard let first = candidates.alternatives.first else {
            throw AIServiceError.parsingError("未返回有效替代动作")
        }
        return SwapResult(
            replacement: first,
            sessionTargetCalories: candidates.sessionTargetCalories,
            sessionTargetMinutes: candidates.sessionTargetMinutes,
            replanNote: candidates.replanNote,
            addToExcludedList: candidates.addToExcludedList
        )
    }

    private static func parseExercise(_ item: ExerciseJSON) -> WorkoutPlanEngine.PlannedExercise? {
        guard let name = item.name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else {
            return nil
        }
        return WorkoutPlanEngine.PlannedExercise(
            name: name,
            muscleGroup: item.muscleGroup ?? "",
            equipment: item.equipment ?? "",
            sets: max(item.sets ?? 3, 1),
            reps: item.reps ?? "12",
            restSeconds: max(item.restSeconds ?? 60, 0),
            targetCalories: max(item.targetCalories ?? 30, 5),
            notes: item.notes ?? "",
            exerciseKind: item.exerciseKind ?? "strength"
        )
    }

    private static func resolvedMoodReminder(from item: SessionJSON, workoutType: String) -> String {
        let trimmed = item.moodReminder?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard trimmed.isEmpty else { return trimmed }
        let activity: WorkoutPlanType = workoutType.contains("泳") ? .swimming : .dance
        return MoodWorkoutTips.randomReminder(for: activity)
    }

    private static func normalizeIntensity(_ raw: String?) -> String {
        switch raw?.lowercased() {
        case "low", "低", "低强度": return "low"
        case "high", "高", "高强度": return "high"
        default: return "medium"
        }
    }

    private static func extractJSONObject(from text: String) -> String {
        if let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}") {
            return String(text[start...end])
        }
        return text
    }
}
