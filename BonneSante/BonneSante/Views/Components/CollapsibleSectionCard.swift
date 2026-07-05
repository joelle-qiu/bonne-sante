import SwiftUI

/// 可折叠卡片区块（训练计划配置、AI 教练等）
/// @author jiali.qiu
struct CollapsibleSectionCard<Content: View>: View {
    let title: String
    let systemImage: String
    let subtitle: String
    @Binding var isExpanded: Bool
    @ViewBuilder var content: () -> Content

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(Theme.Motion.cardSpring) { isExpanded.toggle() }
            } label: {
                HStack {
                    Label(title, systemImage: systemImage)
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Text(isExpanded ? "收起" : "展开")
                        .font(.caption)
                        .foregroundStyle(Theme.adaptiveTextSecondary(colorScheme))
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption.weight(.semibold))
                }
            }
            .buttonStyle(.plain)

            if !subtitle.isEmpty {
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(Theme.adaptiveTextSecondary(colorScheme))
            }

            if isExpanded {
                content()
            }
        }
        .morandiCard()
    }
}
