import Foundation

struct NutritionInfo: Codable {
    let foodName: String
    let grams: Double
    let calories: Double
    let protein: Double
    let carbohydrates: Double
    let fat: Double
    let confidence: String
    let notes: String?
    let daysAgo: Int?
    let mealType: String?

    enum CodingKeys: String, CodingKey {
        case foodName = "food_name"
        case grams, calories, protein, carbohydrates, fat, confidence, notes
        case daysAgo = "days_ago"
        case mealType = "meal_type"
    }

    var entryDate: Date {
        let days = daysAgo ?? 0
        return Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
    }

    var resolvedMealType: MealType {
        MealType.fromAIValue(mealType) ?? MealType.inferredFromTime(entryDate)
    }

    init(foodName: String, grams: Double, calories: Double, protein: Double,
         carbohydrates: Double, fat: Double, confidence: String,
         notes: String? = nil, daysAgo: Int? = 0, mealType: MealType? = nil) {
        self.foodName = foodName
        self.grams = grams
        self.calories = calories
        self.protein = protein
        self.carbohydrates = carbohydrates
        self.fat = fat
        self.confidence = confidence
        self.notes = notes
        self.daysAgo = daysAgo
        self.mealType = mealType?.rawValue
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        foodName = try container.decode(String.self, forKey: .foodName)

        grams = try Self.decodeFlexibleDouble(from: container, forKey: .grams) ?? 100
        calories = try Self.decodeFlexibleDouble(from: container, forKey: .calories) ?? 0
        protein = try Self.decodeFlexibleDouble(from: container, forKey: .protein) ?? 0
        carbohydrates = try Self.decodeFlexibleDouble(from: container, forKey: .carbohydrates) ?? 0
        fat = try Self.decodeFlexibleDouble(from: container, forKey: .fat) ?? 0

        confidence = (try? container.decode(String.self, forKey: .confidence)) ?? "medium"

        notes = try? container.decode(String.self, forKey: .notes)
        daysAgo = try? container.decode(Int.self, forKey: .daysAgo)
        mealType = try? container.decode(String.self, forKey: .mealType)
    }

    func withMealType(_ meal: MealType) -> NutritionInfo {
        NutritionInfo(
            foodName: foodName,
            grams: grams,
            calories: calories,
            protein: protein,
            carbohydrates: carbohydrates,
            fat: fat,
            confidence: confidence,
            notes: notes,
            daysAgo: daysAgo,
            mealType: meal
        )
    }

    private static func decodeFlexibleDouble(from container: KeyedDecodingContainer<CodingKeys>, forKey key: CodingKeys) throws -> Double? {
        if let value = try? container.decode(Double.self, forKey: key) {
            return value
        }
        if let value = try? container.decode(Int.self, forKey: key) {
            return Double(value)
        }
        if let stringValue = try? container.decode(String.self, forKey: key) {
            return Double(stringValue)
        }
        return nil
    }
}
