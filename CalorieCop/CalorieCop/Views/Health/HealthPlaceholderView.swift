import SwiftUI

/// 健康档案占位（阶段二实现）
/// @author jiali.qiu
struct HealthPlaceholderView: View {
    var body: some View {
        NavigationStack {
            EmptyStateView(
                symbol: "list.clipboard",
                title: "健康档案",
                message: "阶段二将支持导入体检报告截图或 PDF，建立指标时间线与风险评估。",
                actionTitle: nil,
                action: nil
            )
            .background(Theme.pageBackground(colorScheme).ignoresSafeArea())
            .navigationTitle("档案")
        }
    }

    @Environment(\.colorScheme) private var colorScheme
}

#Preview {
    HealthPlaceholderView()
}
