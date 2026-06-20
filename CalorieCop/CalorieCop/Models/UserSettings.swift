import Foundation
import SwiftData

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

    // Conversion factors
    static let kgToLb: Double = 2.20462
    static let lbToKg: Double = 0.453592

    /// Convert a weight value from kg to this unit
    func fromKg(_ kg: Double) -> Double {
        switch self {
        case .kg: return kg
        case .lb: return kg * Self.kgToLb
        }
    }

    /// Convert a weight value from this unit to kg
    func toKg(_ value: Double) -> Double {
        switch self {
        case .kg: return value
        case .lb: return value * Self.lbToKg
        }
    }

    /// Format weight with unit
    func format(_ kgValue: Double) -> String {
        let value = fromKg(kgValue)
        return String(format: "%.1f %@", value, shortName)
    }
}

@Model
final class UserSettings {
    var weightUnit: String  // Store as String for SwiftData compatibility
    var createdAt: Date

    init(weightUnit: WeightUnit = .kg) {
        self.weightUnit = weightUnit.rawValue
        self.createdAt = Date()
    }

    var preferredWeightUnit: WeightUnit {
        get { WeightUnit(rawValue: weightUnit) ?? .kg }
        set { weightUnit = newValue.rawValue }
    }
}
