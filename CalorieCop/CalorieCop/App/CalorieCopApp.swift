import SwiftUI
import SwiftData

@main
struct CalorieCopApp: App {
    @State private var healthContext = UnifiedHealthContext()

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            FoodEntry.self,
            UserGoal.self,
            WeightEntry.self,
            UserSettings.self,
            ChatMessage.self,
            FoodPreference.self,
            CycleProfile.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            AppRootView()
                .healthContext(healthContext)
                .tint(Theme.primary)
                .onAppear {
                    let context = sharedModelContainer.mainContext
                    DataMigrationService.migrateIfNeeded(modelContext: context)
                }
                .task {
                    await healthContext.healthKitService.requestAuthorization()
                }
        }
        .modelContainer(sharedModelContainer)
    }
}
