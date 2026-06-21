import Foundation
import SwiftUI

/// 月经周期阶段计算、HealthKit 合并与 tips 知识库
/// @author jiali.qiu
enum CycleEngine {

    enum DataSource: String, Sendable {
        case manual
        case healthKit
        case merged

        var label: String {
            switch self {
            case .manual: return "手动设置"
            case .healthKit: return "Apple 健康"
            case .merged: return "健康 + 手动"
            }
        }
    }

    struct PhaseInfo: Sendable {
        var phase: CyclePhase
        var cycleDay: Int
        var label: String
        var tip: String
        var dietTip: String
        var workoutTip: String
        var dataSource: DataSource
        var daysUntilNextPeriod: Int?
        var predictedNextPeriodStart: Date?
    }

    struct EffectiveProfile: Sendable {
        let lastPeriodStart: Date
        let averageCycleLength: Int
        let averagePeriodLength: Int
        let dataSource: DataSource
    }

    // MARK: - Public API

    static func phaseInfo(
        from profile: CycleProfile?,
        healthKit: MenstrualCycleSnapshot? = nil,
        on date: Date = Date()
    ) -> PhaseInfo {
        guard let effective = resolveEffectiveProfile(manual: profile, healthKit: healthKit) else {
            return unknownPhaseInfo()
        }

        let day = cycleDay(
            since: effective.lastPeriodStart,
            on: date,
            cycleLength: effective.averageCycleLength
        )
        let phase = resolvePhase(
            day: day,
            periodLength: effective.averagePeriodLength,
            cycleLength: effective.averageCycleLength
        )
        let tips = dailyTips(for: phase, cycleDay: day)
        let nextStart = predictedNextPeriodStart(
            lastPeriodStart: effective.lastPeriodStart,
            cycleLength: effective.averageCycleLength,
            after: date
        )
        let daysUntil: Int? = nextStart.flatMap {
            Calendar.current.dateComponents(
                [.day],
                from: Calendar.current.startOfDay(for: date),
                to: Calendar.current.startOfDay(for: $0)
            ).day
        }

        return PhaseInfo(
            phase: phase,
            cycleDay: day,
            label: "\(phase.rawValue) · 第\(day)天",
            tip: tips.combined,
            dietTip: tips.diet,
            workoutTip: tips.workout,
            dataSource: effective.dataSource,
            daysUntilNextPeriod: daysUntil,
            predictedNextPeriodStart: nextStart
        )
    }

    /// 将 HealthKit 快照写入 SwiftData 配置（设置页「同步」调用）
    static func applyHealthKitSnapshot(
        _ snapshot: MenstrualCycleSnapshot,
        to profile: CycleProfile
    ) -> Bool {
        guard let start = snapshot.lastPeriodStart else { return false }
        profile.lastPeriodStart = start
        if let cycle = snapshot.inferredCycleLength {
            profile.averageCycleLength = cycle
        }
        if let period = snapshot.inferredPeriodLength {
            profile.averagePeriodLength = period
        }
        profile.dataSource = DataSource.healthKit.rawValue
        profile.lastSyncedAt = Date()
        return true
    }

    static func cycleDay(since lastPeriodStart: Date, on date: Date, cycleLength: Int) -> Int {
        let start = Calendar.current.startOfDay(for: lastPeriodStart)
        let today = Calendar.current.startOfDay(for: date)
        let days = Calendar.current.dateComponents([.day], from: start, to: today).day ?? 0
        let len = max(cycleLength, 1)
        let normalized = ((days % len) + len) % len
        return normalized + 1
    }

    static func resolvePhase(day: Int, periodLength: Int, cycleLength: Int) -> CyclePhase {
        if day <= periodLength { return .menstrual }
        let ovulationApprox = max(cycleLength - 14, periodLength + 1)
        if day < ovulationApprox { return .follicular }
        return .luteal
    }

    static func predictedNextPeriodStart(
        lastPeriodStart: Date,
        cycleLength: Int,
        after date: Date = Date()
    ) -> Date? {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: lastPeriodStart)
        let today = calendar.startOfDay(for: date)
        let len = max(cycleLength, 1)
        var candidate = start
        while candidate <= today {
            guard let next = calendar.date(byAdding: .day, value: len, to: candidate) else { return nil }
            candidate = next
        }
        return candidate
    }

    // MARK: - Tips 知识库

    static func dailyTips(for phase: CyclePhase, cycleDay: Int) -> (diet: String, workout: String, combined: String) {
        let bank = tipsBank(for: phase)
        guard !bank.diet.isEmpty else {
            let fallback = "设置周期后，这里会显示针对当前阶段的建议。"
            return (fallback, fallback, fallback)
        }
        let index = max(cycleDay - 1, 0) % bank.diet.count
        let diet = bank.diet[index]
        let workout = bank.workout[index % bank.workout.count]
        return (diet, workout, "\(diet) \(workout)")
    }

    private static func tipsBank(for phase: CyclePhase) -> (diet: [String], workout: [String]) {
        switch phase {
        case .menstrual:
            return (
                diet: [
                    "经期多摄入富含铁的食物，如瘦肉、菠菜与红枣。",
                    "多喝温水，减少生冷与刺激性饮食。",
                    "适量补充优质蛋白，帮助恢复体力。"
                ],
                workout: [
                    "以散步、温和拉伸为主，避免高强度训练。",
                    "可做骨盆底舒缓练习，注意腰腹保暖。",
                    "感到疲劳时优先休息，不必勉强完成运动量。"
                ]
            )
        case .follicular:
            return (
                diet: [
                    "卵泡期体能回升，可适当增加优质碳水与蛋白质。",
                    "多吃新鲜蔬菜，维持稳定血糖与饱腹感。",
                    "训练日可适当提高热量，训练后及时补充。"
                ],
                workout: [
                    "适合力量训练与有氧组合，可尝试提高训练强度。",
                    "本周可安排 2–3 次中等强度锻炼。",
                    "运动后做好拉伸，关注肩背与髋部灵活性。"
                ]
            )
        case .luteal:
            return (
                diet: [
                    "黄体期易馋甜食，用坚果、酸奶替代高糖零食。",
                    "增加膳食纤维，减轻腹胀与水肿感。",
                    "控制盐分摄入，帮助缓解黄体期不适。"
                ],
                workout: [
                    "降低高强度训练，瑜伽、普拉提和快走更友好。",
                    "以中等强度维持活动量，避免过度透支。",
                    "关注睡眠与恢复，训练前后充分热身放松。"
                ]
            )
        case .unknown:
            return (diet: [], workout: [])
        }
    }

    // MARK: - Profile Merge

    static func resolveEffectiveProfile(
        manual: CycleProfile?,
        healthKit: MenstrualCycleSnapshot?
    ) -> EffectiveProfile? {
        let hkStart = healthKit?.lastPeriodStart
        let manualStart = manual.map(\.lastPeriodStart)

        guard hkStart != nil || manualStart != nil else { return nil }

        let useHealthKitStart: Bool = {
            guard let hk = hkStart, let manual = manualStart else { return hkStart != nil }
            return hk >= manual
        }()

        let lastStart = useHealthKitStart ? (hkStart ?? manualStart!) : (manualStart ?? hkStart!)
        let cycleLength = healthKit?.inferredCycleLength
            ?? manual?.averageCycleLength
            ?? 28
        let periodLength = healthKit?.inferredPeriodLength
            ?? manual?.averagePeriodLength
            ?? 5

        let source: DataSource = {
            if hkStart != nil && manualStart != nil { return .merged }
            if hkStart != nil { return .healthKit }
            return .manual
        }()

        return EffectiveProfile(
            lastPeriodStart: lastStart,
            averageCycleLength: min(max(cycleLength, 21), 45),
            averagePeriodLength: min(max(periodLength, 2), 10),
            dataSource: source
        )
    }

    private static func unknownPhaseInfo() -> PhaseInfo {
        PhaseInfo(
            phase: .unknown,
            cycleDay: 0,
            label: "周期未设置",
            tip: "在「我的」中设置末次月经，或从 Apple 健康同步经期数据。",
            dietTip: "设置周期后获取饮食建议。",
            workoutTip: "设置周期后获取训练建议。",
            dataSource: .manual,
            daysUntilNextPeriod: nil,
            predictedNextPeriodStart: nil
        )
    }
}

// MARK: - Environment

private struct CyclePhaseKey: EnvironmentKey {
    static let defaultValue: CyclePhase = .unknown
}

extension EnvironmentValues {
    var cyclePhase: CyclePhase {
        get { self[CyclePhaseKey.self] }
        set { self[CyclePhaseKey.self] = newValue }
    }
}

extension View {
    func cyclePhase(_ phase: CyclePhase) -> some View {
        environment(\.cyclePhase, phase)
    }
}
