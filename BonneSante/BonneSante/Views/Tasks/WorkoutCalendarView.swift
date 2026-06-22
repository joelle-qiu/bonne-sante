import SwiftUI
import SwiftData

/// 运动日历：今日 / 本周仪表盘视图（风格对齐首页能量看板）
/// @author jiali.qiu
struct WorkoutCalendarView: View {
    @Environment(\.healthContext) private var healthContext
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.modelContext) private var modelContext

    @State private var scope: CalendarScope = .today
    @State private var workouts: [WorkoutSnapshot] = []
    @State private var planEntries: [WorkoutPlanEntry] = []
    @State private var selectedDay: Date?

    private enum CalendarScope: String, CaseIterable, Identifiable {
        case today = "今日"
        case week = "本周"
        var id: String { rawValue }
    }

    private var weekStart: Date { WorkoutPlanService.startOfWeek() }
    private var weekEnd: Date { WorkoutPlanService.endOfWeek(from: weekStart) }

    private var todaySummary: WorkoutCalendarEngine.DaySummary {
        WorkoutCalendarEngine.todaySummary(workouts: workouts, planEntries: planEntries)
    }

    private var weekSummaries: [WorkoutCalendarEngine.DaySummary] {
        WorkoutCalendarEngine.weekDaySummaries(workouts: workouts, planEntries: planEntries)
    }

    private var weekStats: WorkoutCalendarEngine.WeekStats {
        WorkoutCalendarEngine.weekStats(for: Date(), workouts: workouts)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Picker("范围", selection: $scope) {
                    ForEach(CalendarScope.allCases) { item in
                        Text(item.rawValue).tag(item)
                    }
                }
                .pickerStyle(.segmented)

                switch scope {
                case .today:
                    todayDashboard
                case .week:
                    weekDashboard
                }

                disclaimer
            }
            .padding(.horizontal, Theme.horizontalPadding)
            .padding(.vertical, 16)
        }
        .cycleThemedPageBackground()
        .navigationTitle("运动日历")
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadData() }
        .refreshable { await loadData() }
        .sheet(item: Binding(
            get: { selectedDay.map { DaySelection(date: $0) } },
            set: { selectedDay = $0?.date }
        )) { selection in
            WorkoutDayDetailSheet(
                date: selection.date,
                workouts: WorkoutCalendarEngine.workouts(on: selection.date, from: workouts)
            )
        }
    }

    // MARK: - Today

    private var todayDashboard: some View {
        VStack(spacing: 16) {
            dayHeroCard(todaySummary, title: "今日运动")

            if let plan = todaySummary.plannedType {
                planCard(
                    type: plan,
                    minutes: todaySummary.planTargetMinutes,
                    calories: todaySummary.planTargetCalories,
                    completed: todaySummary.planCompleted
                )
            }

            let todayWorkouts = WorkoutCalendarEngine.workouts(on: Date(), from: workouts)
            if todayWorkouts.isEmpty {
                emptyDayHint("今天还没有 Apple 健康锻炼记录")
            } else {
                workoutListCard(todayWorkouts, title: "锻炼记录")
            }
        }
    }

    // MARK: - Week

    private var weekDashboard: some View {
        VStack(spacing: 16) {
            weekOverviewCard

            ForEach(weekSummaries) { day in
                Button {
                    selectedDay = day.date
                } label: {
                    weekDayRow(day)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var weekOverviewCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("本周概览")
                    .font(.headline)
                Spacer()
                Text("\(weekStats.activeDays)/\(weekStats.goalDays) 天")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Theme.adaptiveAccent(colorScheme))
            }
            ProgressView(value: Double(weekStats.activeDays), total: Double(max(weekStats.goalDays, 1)))
                .tint(Theme.adaptiveAccent(colorScheme))
            HStack {
                metricTile(icon: "clock.fill", label: "总时长", value: "\(Int(weekStats.totalMinutes))", unit: "分钟", color: Theme.energyActive(colorScheme))
                metricTile(icon: "flame.fill", label: "总消耗", value: "\(Int(weekStats.totalCalories))", unit: "kcal", color: Theme.macroProtein(colorScheme))
            }
        }
        .morandiCard()
    }

    private func weekDayRow(_ day: WorkoutCalendarEngine.DaySummary) -> some View {
        HStack(spacing: 14) {
            VStack(spacing: 2) {
                Text(weekdayShort(day.date))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Theme.adaptiveTextSecondary(colorScheme))
                Text("\(Calendar.current.component(.day, from: day.date))")
                    .font(.headline)
                    .foregroundStyle(day.isToday ? Theme.adaptiveAccent(colorScheme) : Theme.adaptiveTextPrimary(colorScheme))
            }
            .frame(width: 36)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    if day.workoutCount > 0 {
                        Label("\(Int(day.totalMinutes)) 分钟 · \(Int(day.totalCalories)) kcal", systemImage: "figure.run")
                            .font(.subheadline.weight(.medium))
                    } else if let plan = day.plannedType {
                        Label("计划：\(plan)", systemImage: "calendar")
                            .font(.subheadline)
                            .foregroundStyle(Theme.adaptiveTextSecondary(colorScheme))
                    } else {
                        Text("休息")
                            .font(.subheadline)
                            .foregroundStyle(Theme.adaptiveTextSecondary(colorScheme))
                    }
                    Spacer()
                    if day.planCompleted {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Theme.adaptiveAccent(colorScheme))
                    }
                }
                if day.heatLevel > 0 {
                    heatBar(level: day.heatLevel)
                }
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .background(Theme.cardBackground(colorScheme))
        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadiusCard))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cornerRadiusCard)
                .stroke(day.isToday ? Theme.adaptiveAccent(colorScheme).opacity(0.45) : Color.clear, lineWidth: 1.5)
        )
    }

    // MARK: - Shared cards

    private func dayHeroCard(_ day: WorkoutCalendarEngine.DaySummary, title: String) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.headline)
            HStack(spacing: 16) {
                ringMetric(
                    progress: min(day.totalMinutes / max(Double(day.planTargetMinutes), 30), 1),
                    center: "\(Int(day.totalMinutes))",
                    subtitle: "分钟",
                    color: Theme.energyActive(colorScheme)
                )
                ringMetric(
                    progress: min(day.totalCalories / max(day.planTargetCalories, 200), 1),
                    center: "\(Int(day.totalCalories))",
                    subtitle: "kcal",
                    color: Theme.macroProtein(colorScheme)
                )
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(day.workoutCount) 次锻炼")
                        .font(.subheadline.weight(.semibold))
                    if day.planTargetMinutes > 0 {
                        Text("计划 \(day.planTargetMinutes) 分钟")
                            .font(.caption)
                            .foregroundStyle(Theme.adaptiveTextSecondary(colorScheme))
                    }
                    if day.heatLevel > 0 {
                        Text(heatLabel(day.heatLevel))
                            .font(.caption.weight(.medium))
                            .foregroundStyle(Theme.adaptiveAccent(colorScheme))
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .morandiCard()
    }

    private func planCard(type: String, minutes: Int, calories: Double, completed: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: completed ? "checkmark.seal.fill" : "figure.run")
                .font(.title2)
                .foregroundStyle(completed ? Theme.adaptiveAccent(colorScheme) : Theme.brandPrimary(colorScheme))
            VStack(alignment: .leading, spacing: 4) {
                Text("今日训练计划")
                    .font(.caption)
                    .foregroundStyle(Theme.adaptiveTextSecondary(colorScheme))
                Text(type)
                    .font(.headline)
                Text("\(minutes) 分钟 · 目标 \(Int(calories)) kcal")
                    .font(.caption)
                    .foregroundStyle(Theme.adaptiveTextSecondary(colorScheme))
            }
            Spacer()
        }
        .morandiCard()
    }

    private func workoutListCard(_ items: [WorkoutSnapshot], title: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            ForEach(items) { item in
                HStack {
                    Text(item.activityLabel)
                        .font(.subheadline)
                    Spacer()
                    Text("\(Int(item.durationMinutes)) 分 · \(Int(item.activeCalories)) kcal")
                        .font(.caption)
                        .foregroundStyle(Theme.adaptiveTextSecondary(colorScheme))
                }
                if item.id != items.last?.id {
                    Divider()
                }
            }
        }
        .morandiCard()
    }

    private func emptyDayHint(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(Theme.adaptiveTextSecondary(colorScheme))
            .frame(maxWidth: .infinity, alignment: .leading)
            .morandiCard()
    }

    private func ringMetric(progress: Double, center: String, subtitle: String, color: Color) -> some View {
        ZStack {
            Circle()
                .stroke(color.opacity(0.18), lineWidth: 8)
                .frame(width: 72, height: 72)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(color, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .frame(width: 72, height: 72)
            VStack(spacing: 0) {
                Text(center)
                    .font(.headline)
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(Theme.adaptiveTextSecondary(colorScheme))
            }
        }
    }

    private func metricTile(icon: String, label: String, value: String, unit: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(label, systemImage: icon)
                .font(.caption)
                .foregroundStyle(Theme.adaptiveTextSecondary(colorScheme))
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(color)
                Text(unit)
                    .font(.caption)
                    .foregroundStyle(Theme.adaptiveTextSecondary(colorScheme))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(color.opacity(colorScheme == .dark ? 0.14 : 0.12))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func heatBar(level: Int) -> some View {
        GeometryReader { geo in
            RoundedRectangle(cornerRadius: 3)
                .fill(Theme.energyActive(colorScheme).opacity(0.15 + Double(level) * 0.2))
                .frame(width: geo.size.width * CGFloat(level) / 3, height: 4)
        }
        .frame(height: 4)
    }

    private func heatLabel(_ level: Int) -> String {
        switch level {
        case 3: return "高强度"
        case 2: return "中等强度"
        default: return "轻度活动"
        }
    }

    private func weekdayShort(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "EEE"
        return formatter.string(from: date)
    }

    private var disclaimer: some View {
        Text("数据来自 Apple 健康；计划场次来自本周训练计划。")
            .font(.caption2)
            .foregroundStyle(Theme.adaptiveTextSecondary(colorScheme))
            .multilineTextAlignment(.center)
    }

    private func loadData() async {
        await healthContext?.healthKitService.fetchWorkouts(from: weekStart, to: weekEnd)
        workouts = healthContext?.healthKitService.recentWorkouts ?? []
        planEntries = WorkoutPlanService.entries(from: weekStart, to: weekEnd, modelContext: modelContext)
    }
}

// MARK: - Day Detail Sheet

private struct DaySelection: Identifiable {
    let date: Date
    var id: TimeInterval { date.timeIntervalSince1970 }
}

private struct WorkoutDayDetailSheet: View {
    let date: Date
    let workouts: [WorkoutSnapshot]

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    private var dateLabel: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日 EEEE"
        return formatter.string(from: date)
    }

    var body: some View {
        NavigationStack {
            List {
                if workouts.isEmpty {
                    ContentUnavailableView(
                        "当天无锻炼记录",
                        systemImage: "figure.run",
                        description: Text("Apple 健康中暂无该日锻炼数据")
                    )
                } else {
                    Section {
                        ForEach(workouts) { item in
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(item.activityLabel)
                                        .font(.headline)
                                    Text(item.date.formatted(date: .omitted, time: .shortened))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                VStack(alignment: .trailing, spacing: 2) {
                                    Text("\(Int(item.durationMinutes)) 分钟")
                                        .font(.subheadline.weight(.semibold))
                                    if item.activeCalories > 0 {
                                        Text("\(Int(item.activeCalories)) kcal")
                                            .font(.caption)
                                            .foregroundStyle(Theme.macroProtein(colorScheme))
                                    }
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    } header: {
                        Text("\(workouts.count) 次 · 共 \(Int(workouts.reduce(0) { $0 + $1.durationMinutes })) 分钟")
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .cycleThemedPageBackground()
            .navigationTitle(dateLabel)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

#Preview {
    NavigationStack {
        WorkoutCalendarView()
    }
    .modelContainer(for: [WorkoutPlanEntry.self], inMemory: true)
    .healthContext(UnifiedHealthContext())
}
