import Foundation
import SwiftData

@Model
final class WeightEntry {
    var id: UUID
    var weight: Double  // kg
    var date: Date
    var source: String  // "manual" or "healthkit"

    init(weight: Double, date: Date = Date(), source: String = "manual") {
        self.id = UUID()
        self.weight = weight
        self.date = date
        self.source = source
    }
}
