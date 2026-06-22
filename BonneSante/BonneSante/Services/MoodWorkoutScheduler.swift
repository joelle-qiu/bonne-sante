import Foundation

/// 心情模式：按天气 + 用户偏好排课，舞蹈/游泳数量尽量均衡
/// @author jiali.qiu
enum MoodWorkoutScheduler {

    struct ScheduledSession: Equatable, Identifiable, Sendable {
        var id: Int { dayOfWeek }
        let dayOfWeek: Int
        let weekdayLabel: String
        let activity: WorkoutPlanType
        let weatherSuggested: WorkoutPlanType
        let weatherSummary: String?
        let isUserOverride: Bool
    }

    private static let weekdayLabels = ["", "周日", "周一", "周二", "周三", "周四", "周五", "周六"]

    /// 排课候选日：周一 → 周日（Calendar.weekday：2=周一 … 1=周日）
    static let weekdayPoolMondayFirst: [Int] = [2, 3, 4, 5, 6, 7, 1]

    /// 天气快照中实际有预报的 weekday（无天气时退回全周）
    static func availableWeekdayPool(weather: WeeklyWeatherSnapshot?) -> [Int] {
        guard let weather, weather.isValid else { return weekdayPoolMondayFirst }
        let available = Set(weather.days.map(\.weekday))
        let filtered = weekdayPoolMondayFirst.filter { available.contains($0) }
        return filtered.isEmpty ? weekdayPoolMondayFirst : filtered
    }

    /// UI 展示：按周一→周日排序的预报行
    static func displayDays(from weather: WeeklyWeatherSnapshot) -> [WeatherDayForecast] {
        weekdayPoolMondayFirst.compactMap { weather.day(forWeekday: $0) }
    }

    static func weekdayLabel(for day: Int) -> String {
        day < weekdayLabels.count ? weekdayLabels[day] : "周?"
    }

    /// 某日最终偏好（用户覆盖 > 天气推荐）
    static func preferredActivity(
        weekday: Int,
        weather: WeeklyWeatherSnapshot?,
        overrides: [Int: WorkoutPlanType]
    ) -> WorkoutPlanType {
        if let override = overrides[weekday] { return override }
        return WeeklyWeatherSnapshot.moodActivity(forWeekday: weekday, weather: weather)
    }

    /// 生成本周 N 场排课（从全周含周末中选最优日期 + 均衡舞蹈/游泳）
    static func schedule(
        sessionsCount: Int,
        weather: WeeklyWeatherSnapshot?,
        overrides: [Int: WorkoutPlanType] = [:],
        pinnedWeekdays: [Int]? = nil
    ) -> [ScheduledSession] {
        let count = min(max(sessionsCount, 2), 6)
        let slotDays: [Int]
        if let pinned = pinnedWeekdays, pinned.count == count, Set(pinned).count == count {
            slotDays = pinned.sorted()
        } else {
            slotDays = pickBestDayCombination(count: count, weather: weather, overrides: overrides)
        }

        let targetSwim = count / 2
        var slots = buildSlotPlans(for: slotDays, weather: weather, overrides: overrides)
        balanceActivities(slots: &slots, targetSwim: targetSwim, weather: weather)

        return slots.map { slot in
            ScheduledSession(
                dayOfWeek: slot.weekday,
                weekdayLabel: weekdayLabel(for: slot.weekday),
                activity: slot.activity,
                weatherSuggested: slot.weatherSuggested,
                weatherSummary: slot.weatherSummary,
                isUserOverride: slot.isUserOverride
            )
        }
        .sorted {
            WorkoutPlanEntry.mondayFirstSortOrder(for: $0.dayOfWeek)
                < WorkoutPlanEntry.mondayFirstSortOrder(for: $1.dayOfWeek)
        }
    }

    /// 供 AI / 规则引擎使用的排课说明
    static func formatScheduleForAI(
        sessions: [ScheduledSession],
        sessionsCount: Int,
        weather: WeeklyWeatherSnapshot?,
        overrides: [Int: WorkoutPlanType]
    ) -> String {
        var lines: [String] = []
        let swimCount = sessions.filter { $0.activity == .swimming }.count
        let danceCount = sessions.count - swimCount

        lines.append("【心情模式 · 本周排课方案】")
        lines.append("总场次 \(sessionsCount) 场/周 · 目标均衡：游泳约 \(sessionsCount / 2) 场、舞蹈约 \(sessionsCount - sessionsCount / 2) 场（当前方案：游泳 \(swimCount) · 舞蹈 \(danceCount)）")
        lines.append("请**严格按下列日期与类型**生成 sessions（勿增删场次）；每场 19:00 左右，写清 targetMinutes、targetCalories、exercises、moodReminder。")

        for (index, session) in sessions.enumerated() {
            var line = "\(index + 1). dayOfWeek=\(session.dayOfWeek)（\(session.weekdayLabel)）→ \(session.activity.label)"
            if let summary = session.weatherSummary {
                line += " · 19:00 · \(summary)"
            }
            if session.isUserOverride {
                line += " · 用户已手动指定类型"
            } else if session.activity != session.weatherSuggested {
                line += " · 为均衡舞蹈/游泳已调整（天气原建议：\(session.weatherSuggested.label)）"
            }
            if session.activity == .swimming {
                line += " · notes 含备物：\(MoodWorkoutTips.swimmingPackingList)"
                if let forecast = weather?.day(forWeekday: session.dayOfWeek), forecast.isStormyEvening {
                    line += " · 雷暴日仅室内泳池"
                }
            }
            lines.append(line)
        }

        if let weather, weather.isValid {
            lines.append("【本周各日天气参考（含周末）】")
            for day in displayDays(from: weather) {
                let pref = preferredActivity(weekday: day.weekday, weather: weather, overrides: overrides)
                let overrideNote = overrides[day.weekday] != nil ? "（用户偏好：\(pref.label)）" : ""
                lines.append("\(day.weekdayLabel) · \(day.eveningSummary) · 天气建议：\(day.moodRecommendedLabel)\(overrideNote)")
            }
        }

        lines.append("""
        【细化要求】
        - 游泳：workoutType=游泳；exercises 1 条蛙泳，reps 写距离如「800米」；targetMinutes 35–45；分段热身/主项/放松
        - 舞蹈：workoutType=舞蹈；exercises 1 条「舞蹈团课」，reps 写「60分钟」；targetMinutes 45–75
        - 每场 moodReminder：1 句不同口语提醒（备物/穿着/热身等），如「别忘带泳帽哦～」
        - 每场 targetCalories 需满足减脂缺口（约每日缺口 30–40% 由训练承担，均摊到各场）
        - 必须输出 weeklyBurnGoalKcal、trainingDayNutrition、restDayNutrition（与专业模式相同，供首页/营养 Tab 同步）
        """)
        return lines.joined(separator: "\n")
    }

    // MARK: - Private

    private struct SlotPlan {
        var weekday: Int
        var activity: WorkoutPlanType
        var weatherSuggested: WorkoutPlanType
        var isUserOverride: Bool
        var weatherSummary: String?
        var weatherScore: Int
    }

    /// 从全周（Mon–Sun）中选总分最高的日期组合
    private static func pickBestDayCombination(
        count: Int,
        weather: WeeklyWeatherSnapshot?,
        overrides: [Int: WorkoutPlanType]
    ) -> [Int] {
        let pool = availableWeekdayPool(weather: weather)
        let combos = combinations(pool, choose: count)
        guard !combos.isEmpty else { return facilityWeekdaySlotsFallback(for: count) }

        var bestDays = combos[0]
        var bestScore = -1

        for days in combos {
            let sorted = days.sorted()
            var slots = buildSlotPlans(for: sorted, weather: weather, overrides: overrides)
            balanceActivities(slots: &slots, targetSwim: count / 2, weather: weather)
            let weatherTotal = slots.reduce(0) { $0 + $1.weatherScore }
            let score = weatherTotal * 10 + spacingScore(sorted)
            if score > bestScore {
                bestScore = score
                bestDays = sorted
            }
        }
        return bestDays
    }

    private static func buildSlotPlans(
        for days: [Int],
        weather: WeeklyWeatherSnapshot?,
        overrides: [Int: WorkoutPlanType]
    ) -> [SlotPlan] {
        days.map { day in
            let suggested = WeeklyWeatherSnapshot.moodActivity(forWeekday: day, weather: weather)
            let resolved = overrides[day] ?? suggested
            let forecast = weather?.day(forWeekday: day)
            return SlotPlan(
                weekday: day,
                activity: resolved,
                weatherSuggested: suggested,
                isUserOverride: overrides[day] != nil,
                weatherSummary: forecast?.eveningSummary,
                weatherScore: weatherFitScore(activity: resolved, forecast: forecast)
            )
        }
    }

    private static func balanceActivities(
        slots: inout [SlotPlan],
        targetSwim: Int,
        weather: WeeklyWeatherSnapshot?
    ) {
        var swimCount = slots.filter { $0.activity == .swimming }.count

        while swimCount > targetSwim {
            guard let index = slots.enumerated()
                .filter({ !$0.element.isUserOverride && $0.element.activity == .swimming })
                .min(by: { $0.element.weatherScore < $1.element.weatherScore })?.offset else { break }
            slots[index].activity = .dance
            slots[index].weatherScore = weatherFitScore(
                activity: .dance,
                forecast: weather?.day(forWeekday: slots[index].weekday)
            )
            swimCount -= 1
        }

        while swimCount < targetSwim {
            guard let index = slots.enumerated()
                .filter({ !$0.element.isUserOverride && $0.element.activity == .dance })
                .max(by: { $0.element.weatherScore < $1.element.weatherScore })?.offset else { break }
            slots[index].activity = .swimming
            slots[index].weatherScore = weatherFitScore(
                activity: .swimming,
                forecast: weather?.day(forWeekday: slots[index].weekday)
            )
            swimCount += 1
        }
    }

    private static func weatherFitScore(activity: WorkoutPlanType, forecast: WeatherDayForecast?) -> Int {
        guard let forecast else { return 0 }
        if activity == .swimming && forecast.isRainyAtEvening { return 12 }
        if activity == .dance && !forecast.isRainyAtEvening { return 10 }
        let precip = forecast.eveningPrecipPercent ?? 50
        return max(0, (50 - precip) / 5)
    }

    private static func spacingScore(_ days: [Int]) -> Int {
        guard days.count >= 2 else { return 5 }
        let sorted = days.map(mondayFirstIndex).sorted()
        return zip(sorted.dropFirst(), sorted).map { $0.0 - $0.1 }.reduce(0, +)
    }

    /// 周一=1 … 周日=7，便于计算日期间距
    private static func mondayFirstIndex(_ weekday: Int) -> Int {
        weekday == 1 ? 7 : weekday - 1
    }

    private static func combinations(_ pool: [Int], choose k: Int) -> [[Int]] {
        guard k > 0, k <= pool.count else { return [] }
        if k == 1 { return pool.map { [$0] } }
        var result: [[Int]] = []
        func backtrack(start: Int, current: [Int]) {
            if current.count == k {
                result.append(current)
                return
            }
            let remaining = k - current.count
            for i in start...(pool.count - remaining) {
                backtrack(start: i + 1, current: current + [pool[i]])
            }
        }
        backtrack(start: 0, current: [])
        return result
    }

    private static func facilityWeekdaySlotsFallback(for count: Int) -> [Int] {
        switch count {
        case 2: return [2, 5]
        case 3: return [2, 4, 6]
        case 4: return [2, 3, 5, 7]
        case 5: return [2, 3, 5, 6, 1]
        default: return [2, 3, 4, 5, 6, 7]
        }
    }
}

// MARK: - Preferences 持久化

extension WorkoutPlanPreferences {

    /// 心情模式用户覆盖：weekday → dance/swimming，格式 `2:swimming,4:dance`
    var moodDayOverrides: [Int: WorkoutPlanType] {
        get {
            guard !moodDayOverridesText.isEmpty else { return [:] }
            var map: [Int: WorkoutPlanType] = [:]
            for part in moodDayOverridesText.split(separator: ",") {
                let pieces = part.split(separator: ":", maxSplits: 1).map(String.init)
                guard pieces.count == 2,
                      let day = Int(pieces[0]),
                      let type = WorkoutPlanType(rawValue: pieces[1]),
                      type == .dance || type == .swimming else { continue }
                map[day] = type
            }
            return map
        }
        set {
            if newValue.isEmpty {
                moodDayOverridesText = ""
            } else {
                moodDayOverridesText = newValue
                    .sorted { $0.key < $1.key }
                    .map { "\($0.key):\($0.value.rawValue)" }
                    .joined(separator: ",")
            }
            updatedAt = Date()
        }
    }

    /// 用户手动固定的排课 weekday 列表，如 `2,4`（空则自动选最优日期）
    var moodPinnedWeekdays: [Int]? {
        get {
            let trimmed = moodPinnedWeekdaysText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            let days = trimmed.split(separator: ",").compactMap { Int($0) }
            return days.isEmpty ? nil : days
        }
        set {
            if let days = newValue, !days.isEmpty {
                moodPinnedWeekdaysText = days.map(String.init).joined(separator: ",")
            } else {
                moodPinnedWeekdaysText = ""
            }
            updatedAt = Date()
        }
    }
}
