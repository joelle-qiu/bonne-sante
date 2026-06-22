import SwiftUI

/// Bonne-Santé 5 Tab 根导航
/// @author jiali.qiu
struct ContentView: View {
    @Environment(\.healthContext) private var healthContext
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        TabView {
            HomeDashboardView()
                .tabItem {
                    Label("首页", systemImage: "heart.text.square.fill")
                }

            HealthTabView()
                .tabItem {
                    Label("健康", systemImage: "list.clipboard")
                }

            WeightLossTabView()
                .tabItem {
                    Label("营养", systemImage: "leaf.fill")
                }

            TasksTabView()
                .tabItem {
                    Label("训练", systemImage: "figure.run")
                }

            SettingsTabView()
                .tabItem {
                    Label("我的", systemImage: "person.crop.circle")
                }
        }
        .tint(tabAccentColor)
        .cyclePhase(healthContext?.cyclePhaseInfo.phase ?? .unknown)
        .animation(.easeInOut(duration: 0.35), value: healthContext?.cyclePhaseInfo.phase)
    }

    private var tabAccentColor: Color {
        let phase = healthContext?.cyclePhaseInfo.phase ?? .unknown
        if phase == .unknown {
            return Theme.brandPrimary(colorScheme)
        }
        return Theme.phaseAccent(phase, colorScheme)
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
            FoodPreference.self,
            Report.self,
            HealthMetric.self,
            RiskFlag.self,
            CheckupPlan.self,
            TodoItem.self,
        ], inMemory: true)
        .healthContext(UnifiedHealthContext())
}
