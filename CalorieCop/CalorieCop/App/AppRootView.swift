import SwiftUI

/// 根视图：首次启动展示 Onboarding，之后进入主界面
/// @author jiali.qiu
struct AppRootView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    var body: some View {
        Group {
            if hasCompletedOnboarding {
                ContentView()
            } else {
                OnboardingView {
                    hasCompletedOnboarding = true
                }
            }
        }
    }
}

#Preview {
    AppRootView()
        .healthContext(UnifiedHealthContext())
}
