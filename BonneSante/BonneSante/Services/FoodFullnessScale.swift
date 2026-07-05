import Foundation

/// 从饮食文字中识别「几分饱 / 吃撑了」等整餐饱度，并用于营养缩放
/// @author jiali.qiu
enum FoodFullnessScale {

    /// 饱度系数：在标准单份估重基础上的缩放比例
    static func mealFactor(from text: String) -> Double? {
        let normalized = text
            .replacingOccurrences(of: " ", with: "")
            .lowercased()

        let rules: [(Double, [String])] = [
            (1.10, ["吃撑了", "撑死了", "吃撑", "太撑", "撑了"]),
            (1.00, ["十分饱", "10分饱", "吃饱", "全饱", "很饱"]),
            (0.90, ["九分饱", "9分饱"]),
            (0.80, ["八分饱", "8分饱"]),
            (0.70, ["七分饱", "7分饱"]),
            (0.60, ["六分饱", "6分饱"]),
            (0.50, ["五分饱", "5分饱", "半饱", "半饱儿"]),
            (0.30, ["三分饱", "3分饱", "三分"]),
            (0.15, ["两分饱", "2分饱", "两口", "浅尝", "尝一口"])
        ]

        for (factor, keywords) in rules {
            if keywords.contains(where: { normalized.contains($0) }) {
                return factor
            }
        }
        return nil
    }

    /// AI notes 是否已说明按饱度调整
    static func notesIndicateFullnessApplied(_ items: [NutritionInfo]) -> Bool {
        items.contains { item in
            guard let notes = item.notes?.lowercased() else { return false }
            return notes.contains("饱") || notes.contains("fullness") || notes.contains("缩放")
        }
    }

    /// 对整餐所有条目统一缩放（仅当 AI 未在 notes 中说明时调用）
    static func applyMealFactorIfNeeded(to items: [NutritionInfo], inputText: String) -> [NutritionInfo] {
        guard let factor = mealFactor(from: inputText), factor != 1.0 else { return items }
        guard !notesIndicateFullnessApplied(items) else { return items }

        let label = fullnessLabel(for: factor)
        return items.map { scale($0, factor: factor, fullnessNote: label) }
    }

    static func fullnessLabel(for factor: Double) -> String {
        switch factor {
        case 1.10: return "吃撑(约110%)"
        case 1.00: return "十分饱"
        case 0.90: return "九分饱"
        case 0.80: return "八分饱"
        case 0.70: return "七分饱"
        case 0.60: return "六分饱"
        case 0.50: return "五分/半饱"
        case 0.30: return "三分饱"
        case 0.15: return "浅尝/两口"
        default: return "饱度\(Int(factor * 100))%"
        }
    }

    private static func scale(_ item: NutritionInfo, factor: Double, fullnessNote: String) -> NutritionInfo {
        let extra = "已按\(fullnessNote)缩放"
        let mergedNotes: String? = {
            if let existing = item.notes, !existing.isEmpty {
                return "\(existing)；\(extra)"
            }
            return extra
        }()

        return NutritionInfo(
            foodName: item.foodName,
            grams: (item.grams * factor).rounded(toPlaces: 1),
            calories: (item.calories * factor).rounded(toPlaces: 1),
            protein: (item.protein * factor).rounded(toPlaces: 1),
            carbohydrates: (item.carbohydrates * factor).rounded(toPlaces: 1),
            fat: (item.fat * factor).rounded(toPlaces: 1),
            confidence: item.confidence,
            notes: mergedNotes,
            daysAgo: item.daysAgo,
            mealType: item.resolvedMealType
        )
    }
}

private extension Double {
    func rounded(toPlaces places: Int) -> Double {
        let divisor = pow(10.0, Double(places))
        return (self * divisor).rounded() / divisor
    }
}
