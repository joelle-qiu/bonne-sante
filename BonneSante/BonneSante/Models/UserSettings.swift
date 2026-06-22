import Foundation
import SwiftData
import SwiftUI

enum WeightUnit: String, Codable, CaseIterable {
    case kg = "kg"
    case lb = "lb"

    var displayName: String {
        switch self {
        case .kg: return "公斤 (kg)"
        case .lb: return "磅 (lb)"
        }
    }

    var shortName: String {
        rawValue
    }

    static let kgToLb: Double = 2.20462
    static let lbToKg: Double = 0.453592

    func fromKg(_ kg: Double) -> Double {
        switch self {
        case .kg: return kg
        case .lb: return kg * Self.kgToLb
        }
    }

    func toKg(_ value: Double) -> Double {
        switch self {
        case .kg: return value
        case .lb: return value * Self.lbToKg
        }
    }

    func format(_ kgValue: Double) -> String {
        let value = fromKg(kgValue)
        return String(format: "%.1f %@", value, shortName)
    }
}

/// 应用外观模式（设置页切换；后续可扩展背景/周期主题）
/// @author jiali.qiu
enum AppAppearanceMode: String, Codable, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: return "跟随系统"
        case .light: return "日间模式"
        case .dark: return "夜间模式"
        }
    }

    var icon: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max.fill"
        case .dark: return "moon.fill"
        }
    }

    /// `nil` 表示跟随系统
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

@Model
final class UserSettings {
    var weightUnit: String
    /// AppAppearanceMode.rawValue
    var appearanceMode: String
    /// 用户称呼（选填，如「小姜」可启用心情健身提示）
    var profileNickname: String
    var createdAt: Date

    init(weightUnit: WeightUnit = .kg, appearanceMode: AppAppearanceMode = .system, profileNickname: String = "") {
        self.weightUnit = weightUnit.rawValue
        self.appearanceMode = appearanceMode.rawValue
        self.profileNickname = profileNickname
        self.createdAt = Date()
    }

    var preferredWeightUnit: WeightUnit {
        get { WeightUnit(rawValue: weightUnit) ?? .kg }
        set { weightUnit = newValue.rawValue }
    }

    var preferredAppearance: AppAppearanceMode {
        get { AppAppearanceMode(rawValue: appearanceMode) ?? .system }
        set { appearanceMode = newValue.rawValue }
    }

    /// 小姜等心情健身用户（称呼含「小姜」）
    var prefersMoodWorkoutProfile: Bool {
        let trimmed = profileNickname.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        let lower = trimmed.lowercased()
        return trimmed.contains("小姜") || lower == "xiaojiang" || lower == "jiang"
    }
}
