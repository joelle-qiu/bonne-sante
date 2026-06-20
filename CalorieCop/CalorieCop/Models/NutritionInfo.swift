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

    enum CodingKeys: String, CodingKey {
        case foodName = "food_name"
        case grams, calories, protein, carbohydrates, fat, confidence, notes
        case daysAgo = "days_ago"
    }

    // Computed property to get the actual date
    var entryDate: Date {
        let days = daysAgo ?? 0
        return Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
    }

    // Custom initializer with default values
    init(foodName: String, grams: Double, calories: Double, protein: Double,
         carbohydrates: Double, fat: Double, confidence: String,
         notes: String? = nil, daysAgo: Int? = 0) {
        self.foodName = foodName
        self.grams = grams
        self.calories = calories
        self.protein = protein
        self.carbohydrates = carbohydrates
        self.fat = fat
        self.confidence = confidence
        self.notes = notes
        self.daysAgo = daysAgo
    }

    // Custom decoder to handle flexible AI responses
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        // Food name - required
        foodName = try container.decode(String.self, forKey: .foodName)

        // Decode numbers flexibly (handle string or number)
        grams = try Self.decodeFlexibleDouble(from: container, forKey: .grams) ?? 100
        calories = try Self.decodeFlexibleDouble(from: container, forKey: .calories) ?? 0
        protein = try Self.decodeFlexibleDouble(from: container, forKey: .protein) ?? 0
        carbohydrates = try Self.decodeFlexibleDouble(from: container, forKey: .carbohydrates) ?? 0
        fat = try Self.decodeFlexibleDouble(from: container, forKey: .fat) ?? 0

        // Confidence with default
        confidence = (try? container.decode(String.self, forKey: .confidence)) ?? "medium"

        // Optional fields
        notes = try? container.decode(String.self, forKey: .notes)
        daysAgo = try? container.decode(Int.self, forKey: .daysAgo)
    }

    // Helper to decode Double from either number or string
    private static func decodeFlexibleDouble(from container: KeyedDecodingContainer<CodingKeys>, forKey key: CodingKeys) throws -> Double? {
        // Try as Double first
        if let value = try? container.decode(Double.self, forKey: key) {
            return value
        }
        // Try as Int
        if let value = try? container.decode(Int.self, forKey: key) {
            return Double(value)
        }
        // Try as String
        if let stringValue = try? container.decode(String.self, forKey: key) {
            return Double(stringValue)
        }
        return nil
    }
}
