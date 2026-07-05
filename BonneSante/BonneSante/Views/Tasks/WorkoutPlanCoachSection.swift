import SwiftUI
import SwiftData

/// 训练计划页 AI 教练（读取 App 内完整健康档案 + 本周排课）
/// @author jiali.qiu
struct WorkoutPlanCoachSection: View {
    let weekStart: Date
    let weekEntries: [WorkoutPlanEntry]
    let exercisesBySession: [UUID: [WorkoutExercise]]
    let todayEntry: WorkoutPlanEntry?
    let phaseLabel: String
    let healthProfile: String
    let genderLabel: String?
    var onPlanUpdated: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.modelContext) private var modelContext

    @State private var expanded = false
    @State private var question = ""
    @State private var messages: [ChatMessage] = []
    @State private var isLoading = false
    @State private var toastMessage: String?

    private var threadKey: String {
        "plan_week_\(Int(weekStart.timeIntervalSince1970))"
    }

    private var planContext: String {
        WorkoutPlanPrompt.planWeekCoachContext(
            entries: weekEntries,
            exercisesBySession: exercisesBySession,
            phaseLabel: phaseLabel,
            todayEntry: todayEntry
        )
    }

    private let quickPrompts = [
        "结合我的体重和体脂，这周训练强度合适吗？",
        "今天练完还需要加有氧吗？",
        "导入今日训练计划",
        "根据本周消耗给我调整建议"
    ]

    var body: some View {
        CollapsibleSectionCard(
            title: "AI 健身教练",
            systemImage: "sparkles",
            subtitle: "已接入近30天体重、锻炼消耗、活动与摄入趋势，无需重复填写。",
            isExpanded: $expanded
        ) {
            VStack(alignment: .leading, spacing: 10) {
                if messages.isEmpty {
                    CoachMessageBubble(
                        text: "我是你的 AI 健身教练。可问训练强度、动作调整、消耗分析；有今日排课时可说「导入今日训练计划」。",
                        isUser: false,
                        compact: true
                    )
                }
                ForEach(messages, id: \.id) { msg in
                    CoachMessageBubble(text: msg.content, isUser: msg.role == "user", compact: true)
                }
                if isLoading {
                    ProgressView().frame(maxWidth: .infinity)
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(quickPrompts, id: \.self) { prompt in
                            CoachQuickPromptButton(title: prompt, compact: true) {
                                question = prompt
                                Task { await send() }
                            }
                        }
                    }
                }

                HStack(spacing: 10) {
                    TextField("问教练…", text: $question, axis: .vertical)
                        .lineLimit(1...3)
                        .foregroundStyle(Theme.adaptiveTextPrimary(colorScheme))
                    Button {
                        Task { await send() }
                    } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.title2)
                            .foregroundStyle(
                                question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isLoading
                                    ? Theme.adaptiveTextTertiary(colorScheme)
                                    : Theme.brandPrimary(colorScheme)
                            )
                    }
                    .disabled(question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isLoading)
                }
            }
        }
        .onAppear { loadHistory() }
        .alert("提示", isPresented: Binding(
            get: { toastMessage != nil },
            set: { if !$0 { toastMessage = nil } }
        )) {
            Button("好的", role: .cancel) {}
        } message: {
            Text(toastMessage ?? "")
        }
    }

    private func loadHistory() {
        let key = threadKey
        let descriptor = FetchDescriptor<ChatMessage>(
            predicate: #Predicate<ChatMessage> {
                $0.channel == "workout_coach" && $0.threadKey == key
            },
            sortBy: [SortDescriptor(\.createdAt)]
        )
        messages = ((try? modelContext.fetch(descriptor)) ?? [])
            .filter { !$0.content.isEmpty }
    }

    private func send() async {
        let q = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        question = ""

        let userMessage = ChatMessage(
            role: "user",
            content: q,
            channel: ChatMessageChannel.workoutCoach,
            threadKey: threadKey
        )
        modelContext.insert(userMessage)
        messages.append(userMessage)
        try? modelContext.save()
        isLoading = true
        defer { isLoading = false }

        let context = planContext
        let history = messages
            .filter { $0.id != userMessage.id && !$0.content.isEmpty }
            .map { (role: $0.role, content: $0.content) }

        let command = WorkoutCoachCommand.parse(q)
        do {
            let assistantText: String
            switch command {
            case .importTodayPlan:
                assistantText = try await handleImportPlan(context: context, history: history, userMessage: q)
            case .chat:
                let rawReply = try await WorkoutPlanAIService.coachReply(
                    sessionContext: context,
                    question: q,
                    history: history,
                    genderLabel: genderLabel,
                    healthProfile: healthProfile
                )
                let (display, _) = WorkoutCoachPlanParser.splitDisplayAndDraft(rawReply)
                assistantText = display.isEmpty ? rawReply : display
            }

            appendAssistant(assistantText)
        } catch {
            appendAssistant("抱歉，出现了错误：\(error.localizedDescription)")
        }
    }

    private func appendAssistant(_ text: String) {
        let msg = ChatMessage(
            role: "assistant",
            content: text,
            channel: ChatMessageChannel.workoutCoach,
            threadKey: threadKey
        )
        modelContext.insert(msg)
        messages.append(msg)
        try? modelContext.save()
        pruneHistory()
    }

    private func pruneHistory() {
        let overflow = messages.count - ChatMessageChannel.maxContextMessages
        guard overflow > 0 else { return }
        for message in messages.prefix(overflow) {
            modelContext.delete(message)
        }
        messages.removeFirst(overflow)
        try? modelContext.save()
    }

    private func handleImportPlan(
        context: String,
        history: [(role: String, content: String)],
        userMessage: String
    ) async throws -> String {
        guard let entry = todayEntry else {
            return "今天没有排课，无法导入今日计划。你可以先描述想练的内容，或改问本周安排建议。"
        }
        let exs = exercisesBySession[entry.id] ?? []
        let sessionCtx = WorkoutPlanPrompt.sessionSummary(entry: entry, exercises: exs)

        let plan: CoachSessionPlan
        if let draftJSON = WorkoutCoachPlanParser.latestDraftJSON(from: history) {
            plan = try WorkoutCoachPlanParser.parseSessionPlan(from: draftJSON)
        } else {
            plan = try await WorkoutPlanAIService.synthesizeSessionPlanFromConversation(
                sessionContext: sessionCtx,
                history: history,
                latestUserMessage: userMessage,
                genderLabel: genderLabel
            )
        }

        try WorkoutPlanService.applyCoachSessionPlan(
            entry: entry,
            plan: plan,
            modelContext: modelContext
        )
        onPlanUpdated()
        return """
        ✅ 已导入今日训练计划（\(plan.exerciseCount) 个动作）
        \(plan.replanNote)

        以上内容仅供参考，请遵医嘱。
        """
    }
}
