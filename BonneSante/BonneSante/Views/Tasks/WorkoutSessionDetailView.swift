import SwiftUI
import SwiftData

/// 单场训练详情：动作清单、组数进度、换动作、AI 教练
/// @author jiali.qiu
struct WorkoutSessionDetailView: View {
    let entry: WorkoutPlanEntry

    @Environment(\.modelContext) private var modelContext
    @Environment(\.healthContext) private var healthContext
    @Environment(\.colorScheme) private var colorScheme

    @Query private var preferencesList: [WorkoutPlanPreferences]

    @State private var exercises: [WorkoutExercise] = []
    @State private var exerciseToSwap: WorkoutExercise?
    @State private var showCoach = false
    @State private var errorMessage: String?

    private var preferences: WorkoutPlanPreferences {
        preferencesList.first ?? WorkoutPlanPreferences()
    }

    private var setProgress: WorkoutPlanService.SetProgress {
        WorkoutPlanService.setProgress(for: exercises)
    }

    private var watchActiveKcal: Double {
        guard let ctx = healthContext else { return 0 }
        return WorkoutPlanService.watchActiveKcal(
            for: entry,
            energyProfile: ctx.healthKitService.energyProfile,
            workouts: ctx.healthKitService.recentWorkouts
        )
    }

    private var watchBurnProgress: Double {
        guard entry.targetCalories > 0, watchActiveKcal > 0 else { return 0 }
        return min(watchActiveKcal / entry.targetCalories, 1)
    }

    private var hasWatchBurnData: Bool {
        healthContext?.healthKitService.energyProfile.hasWatchData == true && watchActiveKcal > 0
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                sessionHeader
                if !entry.moodReminderText.isEmpty {
                    moodReminderCard
                }
                if !entry.replanNote.isEmpty {
                    replanBanner
                }
                exerciseList
                disclaimer
            }
            .padding(.horizontal, Theme.horizontalPadding)
            .padding(.vertical, 16)
        }
        .cycleThemedPageBackground()
        .navigationTitle(entry.weekdayLabel)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showCoach = true
                } label: {
                    Label("AI 教练", systemImage: "sparkles")
                }
            }
        }
        .task {
            reloadExercises()
            await healthContext?.refreshHealthKitOnly()
        }
        .sheet(item: $exerciseToSwap) { exercise in
            ExerciseSwapSheet(
                exercise: exercise,
                entry: entry,
                preferences: preferences,
                onComplete: { reloadExercises() }
            )
        }
        .sheet(isPresented: $showCoach) {
            WorkoutCoachView(entry: entry, exercises: exercises, onPlanUpdated: { reloadExercises() })
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

    private var sessionHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(entry.workoutType)
                    .font(.title3.bold())
                Spacer()
                Text(entry.intensityLabel)
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Theme.primary.opacity(0.25))
                    .clipShape(Capsule())
            }

            HStack(spacing: 16) {
                metricTile(title: "动作组数", value: "\(setProgress.completedSets)/\(setProgress.totalSets)", unit: "组")
                metricTile(
                    title: "Watch 活动",
                    value: hasWatchBurnData ? "\(Int(watchActiveKcal))" : "—",
                    unit: "kcal"
                )
                metricTile(title: "计划时长", value: "\(entry.targetMinutes)", unit: "分钟")
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("动作完成度")
                        .font(.caption)
                    Spacer()
                    Text("\(setProgress.completedSets)/\(setProgress.totalSets) 组")
                        .font(.caption.weight(.semibold))
                }
                ProgressView(value: setProgress.fraction)
                    .tint(Theme.adaptiveAccent(colorScheme))

                HStack {
                    Text("消耗进度（Apple 健康）")
                        .font(.caption)
                    Spacer()
                    if hasWatchBurnData {
                        Text("\(Int(watchActiveKcal)) / 参考 \(Int(entry.targetCalories)) kcal")
                            .font(.caption.weight(.semibold))
                    } else {
                        Text("暂无 Watch 数据")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.adaptiveTextSecondary(colorScheme))
                    }
                }
                ProgressView(value: watchBurnProgress)
                    .tint(Theme.macroProtein(colorScheme))
                Text("组勾选仅统计动作完成；消耗以 Watch 当日活动为准，计划 kcal 仅供参考。")
                    .font(.caption2)
                    .foregroundStyle(Theme.adaptiveTextSecondary(colorScheme))
            }

            if !entry.notes.isEmpty {
                Text(entry.notes)
                    .font(.caption)
                    .foregroundStyle(Theme.adaptiveTextSecondary(colorScheme))
            }

            Menu {
                ForEach(WorkoutSessionFocus.allCases) { focus in
                    Button(focus.label) {
                        WorkoutPlanService.applySessionFocus(entry, focus: focus, modelContext: modelContext)
                        reloadExercises()
                    }
                }
            } label: {
                Label("调整今日侧重", systemImage: "arrow.triangle.2.circlepath")
                    .font(.caption.weight(.medium))
            }
            .foregroundStyle(Theme.adaptiveAccent(colorScheme))
        }
        .morandiCard()
    }

    private var moodReminderCard: some View {
        HStack(alignment: .top, spacing: 10) {
            Text("💬")
                .font(.title3)
            Text(entry.moodReminderText)
                .font(.subheadline)
                .foregroundStyle(Theme.adaptiveTextPrimary(colorScheme))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.energyActive(colorScheme).opacity(0.14))
        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadiusCard))
    }

    private var replanBanner: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .foregroundStyle(Theme.adaptiveAccent(colorScheme))
            Text(entry.replanNote)
                .font(.caption)
                .foregroundStyle(Theme.adaptiveTextPrimary(colorScheme))
        }
        .padding(12)
        .background(Theme.adaptiveAccent(colorScheme).opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadiusCard))
    }

    private var exerciseList: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("动作清单（\(exercises.count) 项）")
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 4)

            if exercises.isEmpty {
                Text("暂无动作细节。请返回重新生成 AI 或规则计划。")
                    .font(.caption)
                    .foregroundStyle(Theme.adaptiveTextSecondary(colorScheme))
                    .morandiCard()
            } else {
                ForEach(Array(exercises.enumerated()), id: \.element.id) { index, exercise in
                    WorkoutExerciseCard(
                        index: index + 1,
                        exercise: exercise,
                        onIncrementSet: {
                            WorkoutPlanService.incrementCompletedSets(exercise, modelContext: modelContext)
                            reloadExercises()
                        },
                        onDecrementSet: {
                            WorkoutPlanService.decrementCompletedSets(exercise, modelContext: modelContext)
                            reloadExercises()
                        },
                        onSwap: { exerciseToSwap = exercise }
                    )
                }
            }
        }
    }

    private var disclaimer: some View {
        Text("动作仅供参考，请遵医嘱。不适立即停止并咨询专业人士。")
            .font(.caption2)
            .foregroundStyle(Theme.adaptiveTextSecondary(colorScheme))
            .multilineTextAlignment(.center)
    }

    private func metricTile(title: String, value: String, unit: String) -> some View {
        VStack(spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(Theme.adaptiveTextSecondary(colorScheme))
            Text(value)
                .font(.headline)
            Text(unit)
                .font(.caption2)
                .foregroundStyle(Theme.adaptiveTextSecondary(colorScheme))
        }
        .frame(maxWidth: .infinity)
    }

    private func reloadExercises() {
        exercises = WorkoutPlanService.exercises(for: entry.id, modelContext: modelContext)
    }
}

// MARK: - Exercise Card

private struct WorkoutExerciseCard: View {
    let index: Int
    let exercise: WorkoutExercise
    let onIncrementSet: () -> Void
    let onDecrementSet: () -> Void
    let onSwap: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    private var muscleTint: Color {
        MuscleGroupPalette.color(for: exercise.muscleGroup, scheme: colorScheme)
    }

    private var setProgress: Double {
        guard exercise.sets > 0 else { return exercise.isFullyCompleted ? 1 : 0 }
        return Double(min(exercise.completedSets, exercise.sets)) / Double(exercise.sets)
    }

    var body: some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(muscleTint)
                .frame(width: 4)

            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top) {
                    Text("\(index)")
                        .font(.caption.bold())
                        .frame(width: 22, height: 22)
                        .background(muscleTint.opacity(0.28))
                        .clipShape(Circle())

                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 6) {
                            Text(exercise.name)
                                .font(.headline)
                            if exercise.wasSubstituted {
                                Text("已更换")
                                    .font(.caption2)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Theme.macroCarbs(colorScheme).opacity(0.3))
                                    .clipShape(Capsule())
                            }
                        }
                        HStack(spacing: 6) {
                            if !exercise.muscleGroup.isEmpty {
                                MuscleGroupBadge(muscleGroup: exercise.muscleGroup)
                            }
                            if !exercise.equipment.isEmpty {
                                Text(exercise.equipment)
                                    .font(.caption2)
                                    .foregroundStyle(Theme.adaptiveTextSecondary(colorScheme))
                            }
                        }
                    }
                    Spacer()
                }

                Text(exercise.setsRepsLabel + (exercise.restSeconds > 0 ? " · 组间 \(exercise.restSeconds)s" : ""))
                    .font(.subheadline)
                    .foregroundStyle(Theme.adaptiveTextPrimary(colorScheme))

                if !exercise.notes.isEmpty {
                    Text(exercise.notes)
                        .font(.caption)
                        .foregroundStyle(Theme.adaptiveTextSecondary(colorScheme))
                }

                if exercise.wasSubstituted, !exercise.swapReason.isEmpty {
                    Text("更换原因：\(exercise.swapReason)")
                        .font(.caption2)
                        .foregroundStyle(Theme.adaptiveTextSecondary(colorScheme))
                }

                ProgressView(value: setProgress)
                    .tint(muscleTint)

                HStack {
                    Text("完成 \(exercise.completedSets)/\(exercise.sets) 组")
                        .font(.caption)
                    Spacer()
                    Button { onDecrementSet() } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.plain)
                    Button { onIncrementSet() } label: {
                        Image(systemName: "plus.circle.fill")
                            .foregroundStyle(muscleTint)
                    }
                    .buttonStyle(.plain)
                    Button(action: onSwap) {
                        Label("换动作", systemImage: "arrow.triangle.swap")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .tint(muscleTint)
                }
            }
            .padding(14)
        }
        .background(Theme.cardBackground(colorScheme))
        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadiusCard))
        .opacity(exercise.isFullyCompleted ? 0.82 : 1)
    }
}

// MARK: - Swap Sheet

struct ExerciseSwapSheet: View {
    let exercise: WorkoutExercise
    let entry: WorkoutPlanEntry
    let preferences: WorkoutPlanPreferences
    var onComplete: () -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @State private var reasonCategory = "器材不可用"
    @State private var reasonDetail = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var candidates: WorkoutPlanAIService.SwapCandidatesResult?
    @State private var selectedIndex: Int?

    private let reasonOptions = ["器材不可用", "关节不适", "难度太高", "暂时不想做", "其他"]

    var body: some View {
        NavigationStack {
            Form {
                Section("无法完成的动作") {
                    HStack(spacing: 0) {
                        Rectangle()
                            .fill(MuscleGroupPalette.color(for: exercise.muscleGroup, scheme: colorScheme))
                            .frame(width: 4)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(exercise.name)
                                .font(.headline)
                            HStack {
                                MuscleGroupBadge(muscleGroup: exercise.muscleGroup)
                                Text(exercise.setsRepsLabel)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.leading, 10)
                    }
                }

                if candidates == nil {
                    reasonSection
                    fetchSection
                } else {
                    candidateSection
                }

                if !preferences.excludedExercises.isEmpty {
                    Section("已避开动作") {
                        Text(preferences.excludedExercises.joined(separator: "、"))
                            .font(.caption)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .cycleThemedPageBackground()
            .navigationTitle("更换动作")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                if candidates != nil {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("确认更换") {
                            Task { await applySelection() }
                        }
                        .disabled(isLoading || selectedIndex == nil)
                    }
                }
            }
            .overlay {
                if isLoading {
                    ProgressView("AI 教练评估中…")
                        .padding()
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
            .alert("失败", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("好的", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var reasonSection: some View {
        Section("原因") {
            Picker("类型", selection: $reasonCategory) {
                ForEach(reasonOptions, id: \.self) { Text($0).tag($0) }
            }
            TextField("补充说明（可选）", text: $reasonDetail, axis: .vertical)
                .lineLimit(2...4)
        }
    }

    private var fetchSection: some View {
        Section {
            Text("AI 将推荐 2–3 个替代动作（按消耗匹配度排序），优先保持本场减脂消耗目标。")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button {
                Task { await fetchCandidates() }
            } label: {
                Label("获取替代方案", systemImage: "sparkles")
            }
            .disabled(isLoading)
        }
    }

    @ViewBuilder
    private var candidateSection: some View {
        if let candidates {
            if !candidates.replanNote.isEmpty {
                Section("重新评估") {
                    Text(candidates.replanNote)
                        .font(.caption)
                    Text("本场目标：\(Int(candidates.sessionTargetCalories)) kcal · \(candidates.sessionTargetMinutes) 分钟")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Section("选择替代动作（\(candidates.alternatives.count) 个）") {
                ForEach(Array(candidates.alternatives.enumerated()), id: \.offset) { index, item in
                    SwapCandidateCard(
                        candidate: item,
                        rank: index + 1,
                        isSelected: selectedIndex == index
                    ) {
                        selectedIndex = index
                    }
                }
            }
        }
    }

    private func composedReason() -> String {
        var reason = reasonCategory
        if !reasonDetail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            reason += "：\(reasonDetail.trimmingCharacters(in: .whitespacesAndNewlines))"
        }
        return reason
    }

    private func fetchCandidates() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let result = try await WorkoutPlanService.fetchSwapCandidates(
                exercise: exercise,
                entry: entry,
                reason: composedReason(),
                preferences: preferences,
                modelContext: modelContext
            )
            candidates = result
            selectedIndex = 0
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func applySelection() async {
        guard let candidates, let index = selectedIndex,
              candidates.alternatives.indices.contains(index) else { return }

        isLoading = true
        defer { isLoading = false }

        do {
            try WorkoutPlanService.applySelectedSwap(
                exercise: exercise,
                entry: entry,
                selected: candidates.alternatives[index],
                candidates: candidates,
                reason: composedReason(),
                preferences: preferences,
                modelContext: modelContext
            )
            onComplete()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Swap Candidate Card

private struct SwapCandidateCard: View {
    let candidate: WorkoutPlanEngine.PlannedExercise
    let rank: Int
    let isSelected: Bool
    let onSelect: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    private var muscleTint: Color {
        MuscleGroupPalette.color(for: candidate.muscleGroup, scheme: colorScheme)
    }

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 0) {
                Rectangle()
                    .fill(muscleTint)
                    .frame(width: 4)

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("方案 \(rank)")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(muscleTint)
                        MuscleGroupBadge(muscleGroup: candidate.muscleGroup)
                        Spacer()
                        if isSelected {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(muscleTint)
                        }
                    }
                    Text(candidate.name)
                        .font(.headline)
                        .foregroundStyle(Theme.adaptiveTextPrimary(colorScheme))
                    Text("\(candidate.setsRepsLabel) · 组间 \(candidate.restSeconds)s · ≈\(Int(candidate.targetCalories)) kcal")
                        .font(.caption)
                        .foregroundStyle(Theme.adaptiveTextSecondary(colorScheme))
                    if !candidate.equipment.isEmpty {
                        Text(candidate.equipment)
                            .font(.caption2)
                            .foregroundStyle(Theme.adaptiveTextSecondary(colorScheme))
                    }
                    if !candidate.notes.isEmpty {
                        Text(candidate.notes)
                            .font(.caption2)
                            .foregroundStyle(Theme.adaptiveTextSecondary(colorScheme))
                    }
                }
                .padding(.vertical, 4)
                .padding(.leading, 10)
            }
        }
        .buttonStyle(.plain)
        .listRowBackground(
            isSelected
                ? muscleTint.opacity(colorScheme == .dark ? 0.15 : 0.12)
                : Color.clear
        )
    }
}

private extension WorkoutPlanEngine.PlannedExercise {
    var setsRepsLabel: String {
        if sets <= 1, reps.contains("分钟") { return reps }
        return "\(sets) 组 × \(reps)"
    }
}

// MARK: - AI Coach

struct WorkoutCoachView: View {
    let entry: WorkoutPlanEntry
    let exercises: [WorkoutExercise]
    var onPlanUpdated: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.modelContext) private var modelContext
    @Query private var userGoals: [UserGoal]

    @State private var question = ""
    @State private var coachMessages: [ChatMessage] = []
    @State private var isLoading = false
    @State private var toastMessage: String?

    private var threadKey: String { entry.id.uuidString }

    private let quickPrompts = [
        "导入今日训练计划",
        "今日想练背和臀",
        "这个动作可以换成什么？",
        "今天练完怎么拉伸？"
    ]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        coachBubble(
                            "我是你的 AI 健身教练。可以说「今日想练…」让我调整动作；满意后发送「导入今日训练计划」写入本场清单。",
                            isUser: false
                        )
                        ForEach(coachMessages, id: \.id) { msg in
                            coachBubble(msg.content, isUser: msg.role == "user")
                        }
                        if isLoading {
                            ProgressView().padding()
                        }
                    }
                    .padding()
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(quickPrompts, id: \.self) { prompt in
                            Button(prompt) {
                                question = prompt
                                Task { await send() }
                            }
                            .font(.caption)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Theme.primary.opacity(0.2))
                            .clipShape(Capsule())
                        }
                    }
                    .padding(.horizontal)
                }
                .padding(.bottom, 8)

                HStack(spacing: 10) {
                    TextField("问教练…", text: $question, axis: .vertical)
                        .lineLimit(1...3)
                    Button {
                        Task { await send() }
                    } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.title2)
                    }
                    .disabled(question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isLoading)
                }
                .padding()
                .background(Theme.cardBackground(colorScheme))
            }
            .cycleThemedPageBackground()
            .navigationTitle("AI 健身教练")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
            .onAppear { loadCoachHistory() }
            .alert("提示", isPresented: Binding(
                get: { toastMessage != nil },
                set: { if !$0 { toastMessage = nil } }
            )) {
                Button("好的", role: .cancel) {}
            } message: {
                Text(toastMessage ?? "")
            }
        }
    }

    private func loadCoachHistory() {
        let key = threadKey
        let descriptor = FetchDescriptor<ChatMessage>(
            predicate: #Predicate<ChatMessage> {
                $0.channel == "workout_coach" && $0.threadKey == key
            },
            sortBy: [SortDescriptor(\.createdAt)]
        )
        coachMessages = ((try? modelContext.fetch(descriptor)) ?? [])
            .filter { !$0.content.isEmpty }
    }

    private func pruneCoachHistory() {
        let overflow = coachMessages.count - ChatMessageChannel.maxContextMessages
        guard overflow > 0 else { return }
        for message in coachMessages.prefix(overflow) {
            modelContext.delete(message)
        }
        coachMessages.removeFirst(overflow)
        try? modelContext.save()
    }

    private func coachBubble(_ text: String, isUser: Bool) -> some View {
        HStack {
            if isUser { Spacer(minLength: 40) }
            Text(text)
                .font(.subheadline)
                .padding(12)
                .background(isUser ? Theme.primary.opacity(0.35) : Theme.cardBackground(colorScheme))
                .clipShape(RoundedRectangle(cornerRadius: 14))
            if !isUser { Spacer(minLength: 40) }
        }
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
        coachMessages.append(userMessage)
        try? modelContext.save()
        isLoading = true
        defer { isLoading = false }

        let context = WorkoutPlanPrompt.sessionSummary(entry: entry, exercises: exercises)
        let history = coachMessages
            .filter { $0.id != userMessage.id && !$0.content.isEmpty }
            .map { (role: $0.role, content: $0.content) }

        let command = WorkoutCoachCommand.parse(q)
        do {
            let assistantText: String
            switch command {
            case .importTodayPlan:
                assistantText = try await handleImportPlan(
                    sessionContext: context,
                    history: history,
                    userMessage: q
                )
            case .chat:
                let rawReply = try await WorkoutPlanAIService.coachReply(
                    sessionContext: context,
                    question: q,
                    history: history,
                    genderLabel: userGoals.first?.genderDisplayLabel
                )
                let (display, _) = WorkoutCoachPlanParser.splitDisplayAndDraft(rawReply)
                assistantText = display.isEmpty ? rawReply : display
            }

            let assistantMessage = ChatMessage(
                role: "assistant",
                content: assistantText,
                channel: ChatMessageChannel.workoutCoach,
                threadKey: threadKey
            )
            modelContext.insert(assistantMessage)
            coachMessages.append(assistantMessage)
            try? modelContext.save()
            pruneCoachHistory()
        } catch {
            let failureText: String
            if case .importTodayPlan = command {
                failureText = "导入失败：\(error.localizedDescription)\n\n请先描述「今日想练…」，或让教练给出动作建议后再试。"
            } else {
                failureText = "抱歉，出现了错误：\(error.localizedDescription)"
            }
            let errorMessage = ChatMessage(
                role: "assistant",
                content: failureText,
                channel: ChatMessageChannel.workoutCoach,
                threadKey: threadKey
            )
            modelContext.insert(errorMessage)
            coachMessages.append(errorMessage)
            try? modelContext.save()
        }
    }

    /// 处理「导入今日训练计划」：优先用对话中的 plan-draft，否则向 AI 合成完整 JSON
    private func handleImportPlan(
        sessionContext: String,
        history: [(role: String, content: String)],
        userMessage: String
    ) async throws -> String {
        let plan: CoachSessionPlan
        if let draftJSON = WorkoutCoachPlanParser.latestDraftJSON(from: history) {
            plan = try WorkoutCoachPlanParser.parseSessionPlan(from: draftJSON)
        } else {
            plan = try await WorkoutPlanAIService.synthesizeSessionPlanFromConversation(
                sessionContext: sessionContext,
                history: history,
                latestUserMessage: userMessage,
                genderLabel: userGoals.first?.genderDisplayLabel
            )
        }

        try WorkoutPlanService.applyCoachSessionPlan(
            entry: entry,
            plan: plan,
            modelContext: modelContext
        )
        onPlanUpdated?()
        await MainActor.run {
            toastMessage = "已更新 \(plan.exerciseCount) 个动作"
        }

        let names = plan.exercises.prefix(5).map(\.name).joined(separator: "、")
        let suffix = plan.exercises.count > 5 ? " 等" : ""
        return """
        ✅ 已导入今日训练计划（\(plan.exerciseCount) 个动作）

        \(plan.workoutType.map { "类型：\($0)\n" } ?? "")目标：\(plan.sessionTargetMinutes) 分钟 · \(Int(plan.sessionTargetCalories)) kcal
        动作：\(names)\(suffix)

        返回训练详情页即可看到更新后的清单。\(plan.replanNote)

        以上内容仅供参考，请遵医嘱。
        """
    }
}

extension WorkoutExercise: Identifiable {}

#Preview {
    NavigationStack {
        WorkoutSessionDetailView(
            entry: WorkoutPlanEntry(
                dayOfWeek: 2,
                workoutType: "力量训练",
                targetMinutes: 45,
                intensity: "medium",
                cyclePhase: "卵泡期",
                weekStartDate: Date(),
                targetCalories: 280
            )
        )
    }
    .modelContainer(for: [WorkoutPlanEntry.self, WorkoutExercise.self, WorkoutPlanPreferences.self], inMemory: true)
}
