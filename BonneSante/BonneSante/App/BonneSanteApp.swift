import SwiftUI
import SwiftData

@main
struct BonneSanteApp: App {
    var sharedModelContainer: ModelContainer = SwiftDataContainerFactory.makeContainer()

    var body: some Scene {
        WindowGroup {
            AppAppearanceHost()
                .onAppear {
                    let context = sharedModelContainer.mainContext
                    DataMigrationService.migrateIfNeeded(modelContext: context)
                }
        }
        .modelContainer(sharedModelContainer)
    }
}

/// 根容器：注入健康上下文 + 用户选择的外观模式
/// @author jiali.qiu
private struct AppAppearanceHost: View {
    @State private var healthContext = UnifiedHealthContext()
    @Query private var settingsList: [UserSettings]
    @Environment(\.modelContext) private var modelContext

    private var appearance: AppAppearanceMode {
        settingsList.first?.preferredAppearance ?? .system
    }

    var body: some View {
        AppRootView()
            .healthContext(healthContext)
            .preferredColorScheme(appearance.colorScheme)
            .tint(Theme.primary)
            .task {
                ensureUserSettings()
                await healthContext.healthKitService.requestAuthorization()
                await TodoService.requestAuthorization()
            }
    }

    private func ensureUserSettings() {
        guard settingsList.isEmpty else { return }
        modelContext.insert(UserSettings())
        try? modelContext.save()
    }
}
