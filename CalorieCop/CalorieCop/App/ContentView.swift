import SwiftUI

/// Bonne-Santé 5 Tab 根导航
/// @author jiali.qiu
struct ContentView: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        TabView {
            HomeDashboardView()
                .tabItem {
                    Label("首页", systemImage: "heart.text.square.fill")
                }

            HealthPlaceholderView()
                .tabItem {
                    Label("健康", systemImage: "list.clipboard")
                }

            WeightLossTabView()
                .tabItem {
                    Label("减脂", systemImage: "figure.mind.and.body")
                }

            TasksPlaceholderView()
                .tabItem {
                    Label("待办", systemImage: "checklist")
                }

            SettingsTabView()
                .tabItem {
                    Label("我的", systemImage: "person.crop.circle")
                }
        }
        .tint(Theme.brandPrimary(colorScheme))
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [
            FoodEntry.self,
            UserGoal.self,
            WeightEntry.self,
            CycleProfile.self,
            ChatMessage.self,
            FoodPreference.self
        ], inMemory: true)
        .healthContext(UnifiedHealthContext())
}
