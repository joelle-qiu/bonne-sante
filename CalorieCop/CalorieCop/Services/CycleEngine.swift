import Foundation

/// 月经周期阶段计算与静态 tips
/// @author jiali.qiu
enum CycleEngine {

    struct PhaseInfo {
        var phase: CyclePhase
        var cycleDay: Int
        var label: String
        var tip: String
    }

    static func phaseInfo(from profile: CycleProfile?, on date: Date = Date()) -> PhaseInfo {
        guard let profile else {
            return PhaseInfo(
                phase: .unknown,
                cycleDay: 0,
                label: "周期未设置",
                tip: "在「我的」中设置末次月经，获取更贴身的建议。"
            )
        }

        let day = cycleDay(since: profile.lastPeriodStart, on: date, cycleLength: profile.averageCycleLength)
        let phase = resolvePhase(day: day, periodLength: profile.averagePeriodLength, cycleLength: profile.averageCycleLength)
        let tip = staticTip(for: phase)

        return PhaseInfo(
            phase: phase,
            cycleDay: day,
            label: "\(phase.rawValue) · 第\(day)天",
            tip: tip
        )
    }

    static func cycleDay(since lastPeriodStart: Date, on date: Date, cycleLength: Int) -> Int {
        let start = Calendar.current.startOfDay(for: lastPeriodStart)
        let today = Calendar.current.startOfDay(for: date)
        let days = Calendar.current.dateComponents([.day], from: start, to: today).day ?? 0
        let len = max(cycleLength, 1)
        return (days % len) + 1
    }

    static func resolvePhase(day: Int, periodLength: Int, cycleLength: Int) -> CyclePhase {
        if day <= periodLength { return .menstrual }
        let ovulationApprox = max(cycleLength - 14, periodLength + 1)
        if day < ovulationApprox { return .follicular }
        return .luteal
    }

    static func staticTip(for phase: CyclePhase) -> String {
        switch phase {
        case .menstrual:
            return "经期适合温和拉伸和散步，注意补铁与保暖。"
        case .follicular:
            return "卵泡期体能回升，可以尝试力量训练或有氧组合。"
        case .luteal:
            return "黄体期降低高强度训练，瑜伽和快走更友好。"
        case .unknown:
            return "设置周期后，这里会显示针对当前阶段的建议。"
        }
    }
}
