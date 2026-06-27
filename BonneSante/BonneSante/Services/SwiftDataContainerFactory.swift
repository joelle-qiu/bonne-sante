import Foundation
import SwiftData

/// SwiftData 容器创建与 schema 版本管理
/// @author zhi.qu
enum SwiftDataContainerFactory {

    /// 模型结构变更时递增，触发旧库清理重建（开发阶段轻量迁移）
    private static let schemaVersion = 19
    private static let schemaVersionKey = "bonnesante_swiftdata_schema_version"

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

        let storedVersion = UserDefaults.standard.integer(forKey: schemaVersionKey)
        if storedVersion > 0 && storedVersion < schemaVersion {
            removeStoreFiles()
        }

        do {
            let container = try ModelContainer(for: schema, configurations: [configuration])
            UserDefaults.standard.set(schemaVersion, forKey: schemaVersionKey)
            return container
        } catch {
            print("[SwiftData] ModelContainer 创建失败: \(error)，尝试清理旧库…")
            removeStoreFiles()
            do {
                let container = try ModelContainer(for: schema, configurations: [configuration])
                UserDefaults.standard.set(schemaVersion, forKey: schemaVersionKey)
                return container
            } catch {
                fatalError("Could not create ModelContainer: \(error)")
            }
        }
    }

    private static func removeStoreFiles() {
        guard let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return
        }
        let names = ["default.store", "default.store-shm", "default.store-wal"]
        for name in names {
            let url = support.appendingPathComponent(name)
            try? FileManager.default.removeItem(at: url)
        }
    }
}
