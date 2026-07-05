import Foundation
import SwiftData

/// 用户月经周期配置
/// @author jiali.qiu
@Model
final class CycleProfile {
    var lastPeriodStart: Date
    var averageCycleLength: Int
    var averagePeriodLength: Int
    /// manual / healthKit / merged
    var dataSource: String
    var lastSyncedAt: Date?

    init(
        lastPeriodStart: Date = Date(),
        averageCycleLength: Int = 28,
        averagePeriodLength: Int = 5,
        dataSource: String = CycleEngine.DataSource.manual.rawValue,
        lastSyncedAt: Date? = nil
    ) {
        self.lastPeriodStart = lastPeriodStart
        self.averageCycleLength = averageCycleLength
        self.averagePeriodLength = averagePeriodLength
        self.dataSource = dataSource
        self.lastSyncedAt = lastSyncedAt
    }

    var sourceType: CycleEngine.DataSource {
        CycleEngine.DataSource(rawValue: dataSource) ?? .manual
    }
}

enum CyclePhase: String, CaseIterable {
    case menstrual = "经期"
    case follicular = "卵泡期"
    case luteal = "黄体期"
    case unknown = "未设置"

    /// 周期阶段主题色（浅色模式基准 hex；展示请用 `Theme.phaseAccent`）
    var themeColorHex: UInt {
        switch self {
        case .menstrual: return 0xB07878
        case .follicular: return 0x5E8266
        case .luteal: return 0x8A7BA8
        case .unknown: return 0xC8C8CD
        }
    }
}
