import Foundation
import SwiftData

/// 单场训练中的具体动作（组数 / 次数 / 目标消耗）
/// @author jiali.qiu
@Model
final class WorkoutExercise {
    var id: UUID
    var sessionId: UUID
    var sortOrder: Int
    var name: String
    var muscleGroup: String
    var equipment: String
    var sets: Int
    /// 次数如「12」或「8-10」；有氧可为「20分钟」
    var reps: String
    var restSeconds: Int
    var targetCalories: Double
    var notes: String
    /// strength | cardio | mobility
    var exerciseKind: String
    var originalName: String
    var swapReason: String
    var completedSets: Int
    var isSkipped: Bool
    var createdAt: Date

    init(
        sessionId: UUID,
        sortOrder: Int,
        name: String,
        muscleGroup: String = "",
        equipment: String = "",
        sets: Int = 3,
        reps: String = "12",
        restSeconds: Int = 60,
        targetCalories: Double = 0,
        notes: String = "",
        exerciseKind: String = "strength",
        originalName: String = "",
        swapReason: String = ""
    ) {
        self.id = UUID()
        self.sessionId = sessionId
        self.sortOrder = sortOrder
        self.name = name
        self.muscleGroup = muscleGroup
        self.equipment = equipment
        self.sets = sets
        self.reps = reps
        self.restSeconds = restSeconds
        self.targetCalories = targetCalories
        self.notes = notes
        self.exerciseKind = exerciseKind
        self.originalName = originalName
        self.swapReason = swapReason
        self.completedSets = 0
        self.isSkipped = false
        self.createdAt = Date()
    }

    var setsRepsLabel: String {
        if exerciseKind == "cardio" || exerciseKind == "mobility" {
            return reps.contains("分钟") ? reps : "\(reps) · \(sets) 组"
        }
        return "\(sets) 组 × \(reps) 次"
    }

    var wasSubstituted: Bool {
        !originalName.isEmpty && originalName != name
    }

    var isFullyCompleted: Bool {
        completedSets >= sets
    }
}
