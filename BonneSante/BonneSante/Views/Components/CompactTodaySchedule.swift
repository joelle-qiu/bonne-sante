import SwiftUI

/// 首页紧凑日程：今日/最近训练 + 临近门诊预约
/// @author jiali.qiu
struct CompactTodaySchedule: View {
    var todayWorkout: WorkoutPlanEntry?
    var todayExerciseCount: Int
    var todayMuscleGroups: [String]
    var nextWorkout: WorkoutPlanEntry?
    var nextWorkoutExerciseCount: Int
    var appointments: [TodoItem]

    @Environment(\.colorScheme) private var colorScheme

    private var hasWorkoutBlock: Bool {
        todayWorkout != nil || nextWorkout != nil
    }

    var body: some View {
        if !hasWorkoutBlock && appointments.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 10) {
                Text("今日日程")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.adaptiveTextPrimary(colorScheme))

                VStack(spacing: 0) {
                    if let todayWorkout {
                        workoutRow(
                            entry: todayWorkout,
                            exerciseCount: todayExerciseCount,
                            muscleGroups: todayMuscleGroups,
                            badge: "今日"
                        )
                        if !appointments.isEmpty {
                            Divider().padding(.leading, 36)
                        }
                    } else if let nextWorkout {
                        workoutRow(
                            entry: nextWorkout,
                            exerciseCount: nextWorkoutExerciseCount,
                            muscleGroups: [],
                            badge: "最近"
                        )
                        if !appointments.isEmpty {
                            Divider().padding(.leading, 36)
                        }
                    }

                    ForEach(Array(appointments.enumerated()), id: \.element.id) { index, item in
                        appointmentRow(item)
                        if index < appointments.count - 1 {
                            Divider().padding(.leading, 36)
                        }
                    }
                }
                .morandiCard()
            }
        }
    }

    @ViewBuilder
    private func workoutRow(
        entry: WorkoutPlanEntry,
        exerciseCount: Int,
        muscleGroups: [String],
        badge: String
    ) -> some View {
        NavigationLink {
            WorkoutSessionDetailView(entry: entry)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: entry.isCompleted ? "checkmark.circle.fill" : "figure.run")
                    .font(.body)
                    .foregroundStyle(entry.isCompleted ? Theme.adaptiveAccent(colorScheme) : Theme.macroProtein(colorScheme))
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(badge)
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Theme.primary.opacity(0.22))
                            .clipShape(Capsule())
                        Text(entry.workoutType)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(Theme.adaptiveTextPrimary(colorScheme))
                    }
                    Text("\(entry.targetMinutes) 分钟 · 目标 \(Int(entry.targetCalories)) kcal")
                        .font(.caption)
                        .foregroundStyle(Theme.adaptiveTextSecondary(colorScheme))
                    if exerciseCount > 0 {
                        HStack(spacing: 6) {
                            Text("\(exerciseCount) 个动作")
                                .font(.caption2)
                                .foregroundStyle(Theme.adaptiveTextSecondary(colorScheme))
                            muscleDots(muscleGroups)
                        }
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(Theme.adaptiveTextSecondary(colorScheme))
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 4)
        }
        .buttonStyle(.plain)
    }

    private func appointmentRow(_ item: TodoItem) -> some View {
        HStack(spacing: 12) {
            Image(systemName: item.calendarEventIdentifier.isEmpty ? "cross.case" : "calendar.badge.checkmark")
                .font(.body)
                .foregroundStyle(Theme.brandPrimary(colorScheme))
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.adaptiveTextPrimary(colorScheme))
                    .lineLimit(1)
                Text(appointmentTimeLabel(item.dueDate))
                    .font(.caption)
                    .foregroundStyle(Theme.adaptiveTextSecondary(colorScheme))
                if !item.department.isEmpty {
                    Text(item.department)
                        .font(.caption2)
                        .foregroundStyle(Theme.adaptiveTextSecondary(colorScheme))
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 4)
    }

    private func muscleDots(_ groups: [String]) -> some View {
        HStack(spacing: 3) {
            ForEach(Array(groups.prefix(5)), id: \.self) { group in
                Circle()
                    .fill(MuscleGroupPalette.color(for: group, scheme: colorScheme))
                    .frame(width: 7, height: 7)
            }
        }
    }

    private func appointmentTimeLabel(_ date: Date) -> String {
        let formatted = date.formatted(date: .abbreviated, time: .shortened)
        let days = Calendar.current.dateComponents(
            [.day],
            from: Calendar.current.startOfDay(for: Date()),
            to: Calendar.current.startOfDay(for: date)
        ).day ?? 0
        if days == 0 { return "\(formatted) · 今天" }
        if days == 1 { return "\(formatted) · 明天" }
        if days > 0 && days <= 7 { return "\(formatted) · \(days) 天后" }
        return formatted
    }
}

#Preview {
    NavigationStack {
        CompactTodaySchedule(
            todayWorkout: nil,
            todayExerciseCount: 0,
            todayMuscleGroups: [],
            nextWorkout: nil,
            nextWorkoutExerciseCount: 0,
            appointments: []
        )
        .padding()
    }
}
