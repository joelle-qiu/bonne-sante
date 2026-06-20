import Foundation
import SwiftData

@Model
final class FoodEntry {
    var id: UUID
    var rawInput: String
    var foodName: String
    var grams: Double
    var calories: Double
    var protein: Double
    var carbohydrates: Double
    var fat: Double
    var createdAt: Date

    init(rawInput: String, foodName: String, grams: Double,
         calories: Double, protein: Double, carbohydrates: Double, fat: Double,
         date: Date = Date()) {
        self.id = UUID()
        self.rawInput = rawInput
        self.foodName = foodName
        self.grams = grams
        self.calories = calories
        self.protein = protein
        self.carbohydrates = carbohydrates
        self.fat = fat
        self.createdAt = date
    }

    convenience init(rawInput: String, nutrition: NutritionInfo) {
        self.init(
            rawInput: rawInput,
            foodName: nutrition.foodName,
            grams: nutrition.grams,
            calories: nutrition.calories,
            protein: nutrition.protein,
            carbohydrates: nutrition.carbohydrates,
            fat: nutrition.fat,
            date: nutrition.entryDate
        )
    }
}
