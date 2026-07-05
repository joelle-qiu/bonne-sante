import Foundation
import SwiftData

/// SwiftData 容器创建（依赖系统轻量迁移，升级前请用 JSON 备份）
/// @author jiali.qiu
enum SwiftDataContainerFactory {

    /// 与 `HealthDataBackupManifest.currentSchemaVersion` 对齐，仅用于备份元数据
    static let schemaVersion = 19

    static func makeContainer() -> ModelContainer {
        let schema = Schema([
            FoodEntry.self,
            UserGoal.self,
            WeightEntry.self,
            UserSettings.self,
            ChatMessage.self,
            FoodPreference.self,
            CycleProfile.self,
            Report.self,
            HealthMetric.self,
            RiskFlag.self,
            CheckupPlan.self,
            TodoItem.self,
            WorkoutPlanEntry.self,
            WorkoutPlanPreferences.self,
            WorkoutExercise.self,
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError(
                """
                Could not create ModelContainer: \(error)
                若刚升级 App，请先在旧版导出 JSON 备份后再导入；勿依赖删库迁移。
                """
            )
        }
    }
}
