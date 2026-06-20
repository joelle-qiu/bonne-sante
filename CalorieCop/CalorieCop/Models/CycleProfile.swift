import Foundation
import SwiftData

/// 用户月经周期配置
/// @author jiali.qiu
@Model
final class CycleProfile {
    var lastPeriodStart: Date
    var averageCycleLength: Int
    var averagePeriodLength: Int

    init(
        lastPeriodStart: Date = Date(),
        averageCycleLength: Int = 28,
        averagePeriodLength: Int = 5
    ) {
        self.lastPeriodStart = lastPeriodStart
        self.averageCycleLength = averageCycleLength
        self.averagePeriodLength = averagePeriodLength
    }
}

enum CyclePhase: String, CaseIterable {
    case menstrual = "经期"
    case follicular = "卵泡期"
    case luteal = "黄体期"
    case unknown = "未设置"

    var themeColorHex: UInt {
        switch self {
        case .menstrual: return 0xF5D0D0
        case .follicular: return 0xD4EDDA
        case .luteal: return 0xE2D4F5
        case .unknown: return 0xE8E8ED
        }
    }
}
