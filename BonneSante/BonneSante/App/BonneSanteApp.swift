import SwiftUI
import SwiftData

@main
struct BonneSanteApp: App {
    @State private var healthContext = UnifiedHealthContext()

    var sharedModelContainer: ModelContainer = SwiftDataContainerFactory.makeContainer()

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
                    await TodoService.requestAuthorization()
                }
        }
        .modelContainer(sharedModelContainer)
    }
}
