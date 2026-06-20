import SwiftUI

/// 待办提醒占位（阶段二实现）
/// @author jiali.qiu
struct TasksPlaceholderView: View {
    var body: some View {
        NavigationStack {
            EmptyStateView(
                symbol: "checklist",
                title: "暂无待办",
                message: "阶段二将支持复查提醒、门诊预约与一键导入系统日历。",
                actionTitle: nil,
                action: nil
            )
            .background(Theme.pageBackground(colorScheme).ignoresSafeArea())
            .navigationTitle("提醒")
        }
    }

    @Environment(\.colorScheme) private var colorScheme
}

#Preview {
    TasksPlaceholderView()
}
