import SwiftUI

/// 连续 7 天运动 · 满月勋章（我的页）
/// @author jiali.qiu
struct ExerciseStreakBadgeCard: View {
    let status: ExerciseStreakEngine.Status

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 14) {
                medalIcon
                VStack(alignment: .leading, spacing: 4) {
                    Text("满月勋章")
                        .font(.headline)
                        .foregroundStyle(Theme.adaptiveTextPrimary(colorScheme))
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(Theme.adaptiveTextSecondary(colorScheme))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                if status.isBadgeUnlocked {
                    Image(systemName: "sparkles")
                        .font(.title3)
                        .foregroundStyle(Theme.adaptiveAccent(colorScheme))
                        .symbolEffect(.pulse, options: .repeating.speed(0.35))
                }
            }

            HStack(spacing: 0) {
                ForEach(status.recentSevenDays) { day in
                    VStack(spacing: 6) {
                        Circle()
                            .fill(dotColor(for: day))
                            .frame(width: day.isToday ? 14 : 11, height: day.isToday ? 14 : 11)
                            .overlay {
                                if day.isToday && !day.isActive {
                                    Circle()
                                        .strokeBorder(Theme.adaptiveAccent(colorScheme), lineWidth: 1.5)
                                }
                            }
                        Text(day.weekdayShort)
                            .font(.system(size: 10, weight: day.isToday ? .semibold : .regular))
                            .foregroundStyle(
                                day.isToday
                                    ? Theme.adaptiveAccent(colorScheme)
                                    : Theme.adaptiveTextTertiary(colorScheme)
                            )
                    }
                    .frame(maxWidth: .infinity)
                }
            }

            if !status.isBadgeUnlocked {
                ProgressView(value: progressFraction)
                    .tint(Theme.energyActive(colorScheme))
            }
        }
        .padding(16)
        .background(Theme.cardBackground(colorScheme))
        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadiusCard))
    }

    private var subtitle: String {
        if status.isBadgeUnlocked {
            if status.currentStreak >= ExerciseStreakEngine.badgeGoalDays {
                return "已连续运动 \(status.currentStreak) 天，保持这个节奏～"
            }
            return "已解锁！继续动下去，身体会记得你的坚持。"
        }
        if status.currentStreak > 0 {
            return "已连续 \(status.currentStreak) 天 · 再 \(status.daysUntilUnlock) 天解锁"
        }
        return "Apple 健康锻炼或完成训练计划均可计入"
    }

    private var progressFraction: Double {
        Double(min(status.currentStreak, ExerciseStreakEngine.badgeGoalDays))
            / Double(ExerciseStreakEngine.badgeGoalDays)
    }

    private var medalIcon: some View {
        ZStack {
            Circle()
                .fill(
                    status.isBadgeUnlocked
                        ? Theme.energyActive(colorScheme).opacity(0.35)
                        : Theme.adaptiveTextTertiary(colorScheme).opacity(0.2)
                )
                .frame(width: 52, height: 52)
            Image(systemName: status.isBadgeUnlocked ? "medal.fill" : "medal")
                .font(.title2)
                .foregroundStyle(
                    status.isBadgeUnlocked
                        ? Theme.energyActive(colorScheme)
                        : Theme.adaptiveTextSecondary(colorScheme)
                )
                .symbolEffect(.bounce, value: status.isBadgeUnlocked)
        }
    }

    private func dotColor(for day: ExerciseStreakEngine.DayDot) -> Color {
        if day.isActive {
            return Theme.energyActive(colorScheme)
        }
        if day.isToday {
            return Theme.adaptiveAccent(colorScheme).opacity(0.2)
        }
        return Theme.adaptiveTextTertiary(colorScheme).opacity(0.25)
    }
}

#Preview("进行中") {
    ExerciseStreakBadgeCard(status: ExerciseStreakEngine.Status(
        currentStreak: 4,
        isBadgeUnlocked: false,
        daysUntilUnlock: 3,
        recentSevenDays: [
            .init(id: "1", weekdayShort: "二", isActive: true, isToday: false),
            .init(id: "2", weekdayShort: "三", isActive: true, isToday: false),
            .init(id: "3", weekdayShort: "四", isActive: false, isToday: false),
            .init(id: "4", weekdayShort: "五", isActive: true, isToday: false),
            .init(id: "5", weekdayShort: "六", isActive: true, isToday: false),
            .init(id: "6", weekdayShort: "日", isActive: false, isToday: false),
            .init(id: "7", weekdayShort: "一", isActive: false, isToday: true)
        ]
    ))
    .padding()
}

#Preview("已解锁") {
    ExerciseStreakBadgeCard(status: ExerciseStreakEngine.Status(
        currentStreak: 9,
        isBadgeUnlocked: true,
        daysUntilUnlock: 0,
        recentSevenDays: (0..<7).map { i in
            .init(id: "\(i)", weekdayShort: "一", isActive: true, isToday: i == 6)
        }
    ))
    .padding()
}
