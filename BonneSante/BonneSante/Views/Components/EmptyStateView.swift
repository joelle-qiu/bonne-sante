import SwiftUI

/// 通用空状态
/// @author jiali.qiu
struct EmptyStateView: View {
    let symbol: String
    let title: String
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: symbol)
                .font(.system(size: 48))
                .foregroundStyle(Theme.brandPrimary(colorScheme))

            Text(title)
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundStyle(Theme.adaptiveTextPrimary(colorScheme))

            Text(message)
                .font(.subheadline)
                .foregroundStyle(Theme.adaptiveTextSecondary(colorScheme))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            if let actionTitle, let action {
                Button(action: action) {
                    Text(actionTitle)
                        .fontWeight(.medium)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Theme.brandPrimary(colorScheme))
                        .foregroundStyle(Theme.adaptiveTextPrimary(colorScheme))
                        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadiusButton))
                }
                .padding(.horizontal, Theme.horizontalPadding)
                .padding(.top, 8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

#Preview {
    EmptyStateView(
        symbol: "list.clipboard",
        title: "还没有健康档案",
        message: "阶段二将支持导入体检报告，建立你的健康时间线。",
        actionTitle: "了解计划",
        action: {}
    )
}
