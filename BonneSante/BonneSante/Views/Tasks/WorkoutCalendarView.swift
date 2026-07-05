import SwiftUI
import SwiftData

/// 运动日历：本月 / 本周轻量视图
/// @author jiali.qiu
struct WorkoutCalendarView: View {
    @Environment(\.healthContext) private var healthContext
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.modelContext) private var modelContext

    @State private var scope: CalendarScope = .month
    @State private var displayMonth: Date = Date()
    @State private var workouts: [WorkoutSnapshot] = []
    @State private var planEntries: [WorkoutPlanEntry] = []
    @State private var selectedDay: Date?

    private enum CalendarScope: String, CaseIterable, Identifiable {
        case month = "本月"
        case week = "本周"
        var id: String { rawValue }
    }

    private var weekStart: Date { WorkoutPlanService.startOfWeek() }
    private var weekEnd: Date { WorkoutPlanService.endOfWeek(from: weekStart) }

    private var monthStart: Date { WorkoutCalendarEngine.startOfMonth(displayMonth) }
    private var monthEnd: Date {
        Calendar.current.date(byAdding: DateComponents(month: 1), to: monthStart) ?? monthStart
    }

    private var monthGrid: [WorkoutCalendarEngine.DayCell] {
        WorkoutCalendarEngine.monthGrid(for: displayMonth, workouts: workouts, planEntries: planEntries)
    }

    private var monthStats: WorkoutCalendarEngine.MonthStats {
        WorkoutCalendarEngine.monthStats(for: displayMonth, workouts: workouts, planEntries: planEntries)
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
                case .month:
                    monthDashboard
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
        .task(id: loadKey) { await loadData() }
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

    private var loadKey: String {
        switch scope {
        case .month:
            return "month-\(Int(monthStart.timeIntervalSince1970))"
        case .week:
            return "week-\(Int(weekStart.timeIntervalSince1970))"
        }
    }

    // MARK: - Month

    private var monthDashboard: some View {
        VStack(spacing: 12) {
            monthHeader
            monthStatsRow
            weekdayHeader
            monthGridView
        }
    }

    private var monthHeader: some View {
        HStack {
            Button {
                shiftMonth(by: -1)
            } label: {
                Image(systemName: "chevron.left")
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.plain)

            Spacer()
            Text(monthTitle)
                .font(.headline)
            Spacer()

            Button {
                shiftMonth(by: 1)
            } label: {
                Image(systemName: "chevron.right")
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.plain)
        }
        .foregroundStyle(Theme.adaptiveTextPrimary(colorScheme))
    }

    private var monthTitle: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy年M月"
        return formatter.string(from: displayMonth)
    }

    private var monthStatsRow: some View {
        HStack(spacing: 8) {
            compactStat("\(monthStats.activeDays)", label: "活跃天")
            compactStat("\(Int(monthStats.totalMinutes))", label: "分钟")
            compactStat("\(Int(monthStats.totalCalories))", label: "kcal")
            if monthStats.plannedDays > 0 {
                compactStat("\(monthStats.completedPlanDays)/\(monthStats.plannedDays)", label: "计划")
            }
        }
    }

    private func compactStat(_ value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.caption.weight(.semibold))
                .monospacedDigit()
            Text(label)
                .fixedFont(size: 9)
                .foregroundStyle(Theme.adaptiveTextSecondary(colorScheme))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(Theme.cardBackground(colorScheme))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var weekdayHeader: some View {
        HStack(spacing: 0) {
            ForEach(["一", "二", "三", "四", "五", "六", "日"], id: \.self) { label in
                Text(label)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(Theme.adaptiveTextSecondary(colorScheme))
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var monthGridView: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 4) {
            ForEach(monthGrid) { cell in
                if cell.isPlaceholder {
                    Color.clear.frame(height: 44)
                } else if let date = cell.date {
                    Button {
                        selectedDay = date
                    } label: {
                        monthDayCell(cell, date: date)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(10)
        .background(Theme.cardBackground(colorScheme))
        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadiusCard))
    }

    private func monthDayCell(_ cell: WorkoutCalendarEngine.DayCell, date: Date) -> some View {
        let calendar = Calendar.current
        let isToday = calendar.isDateInToday(date)
        let day = calendar.component(.day, from: date)

        return VStack(spacing: 3) {
            Text("\(day)")
                .font(.caption.weight(isToday ? .bold : .regular))
                .foregroundStyle(isToday ? Theme.adaptiveAccent(colorScheme) : Theme.adaptiveTextPrimary(colorScheme))

            if cell.workoutCount > 0 {
                Circle()
                    .fill(heatColor(cell.heatLevel))
                    .frame(width: 5, height: 5)
            } else if cell.plannedTitle != nil {
                Circle()
                    .stroke(Theme.adaptiveAccent(colorScheme).opacity(0.5), lineWidth: 1)
                    .frame(width: 5, height: 5)
            } else {
                Color.clear.frame(width: 5, height: 5)
            }

            if cell.planCompleted {
                Image(systemName: "checkmark")
                    .fixedFont(size: 7, weight: .bold)
                    .foregroundStyle(Theme.adaptiveAccent(colorScheme))
            }
        }
        .frame(maxWidth: .infinity, minHeight: 44)
        .background(isToday ? Theme.adaptiveAccent(colorScheme).opacity(0.12) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func heatColor(_ level: Int) -> Color {
        switch level {
        case 3: return Theme.macroProtein(colorScheme)
        case 2: return Theme.energyActive(colorScheme)
        default: return Theme.adaptiveAccent(colorScheme).opacity(0.7)
        }
    }

    private func shiftMonth(by offset: Int) {
        if let next = Calendar.current.date(byAdding: .month, value: offset, to: displayMonth) {
            displayMonth = next
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

    // MARK: - Shared

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

    private func weekdayShort(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "EEE"
        return formatter.string(from: date)
    }

    private var disclaimer: some View {
        Text("数据来自 Apple 健康；计划场次来自训练计划。")
            .font(.caption2)
            .foregroundStyle(Theme.adaptiveTextSecondary(colorScheme))
            .multilineTextAlignment(.center)
    }

    private func loadData() async {
        switch scope {
        case .month:
            await healthContext?.healthKitService.fetchWorkouts(from: monthStart, to: monthEnd)
            workouts = healthContext?.healthKitService.recentWorkouts ?? []
            planEntries = WorkoutPlanService.entries(from: monthStart, to: monthEnd, modelContext: modelContext)
        case .week:
            await healthContext?.healthKitService.fetchWorkouts(from: weekStart, to: weekEnd)
            workouts = healthContext?.healthKitService.recentWorkouts ?? []
            planEntries = WorkoutPlanService.entries(from: weekStart, to: weekEnd, modelContext: modelContext)
        }
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
