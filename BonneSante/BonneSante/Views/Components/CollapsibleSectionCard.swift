import SwiftUI

/// 可折叠卡片区块样式
enum CollapsibleSectionCardStyle {
    case standard
    case coach
}

/// 可折叠卡片区块（训练计划配置、AI 教练等）
/// @author jiali.qiu
struct CollapsibleSectionCard<Content: View>: View {
    let title: String
    let systemImage: String
    let subtitle: String
    var style: CollapsibleSectionCardStyle = .standard
    @Binding var isExpanded: Bool
    @ViewBuilder var content: () -> Content

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(Theme.Motion.cardSpring) { isExpanded.toggle() }
            } label: {
                HStack {
                    Label {
                        Text(title)
                    } icon: {
                        Image(systemName: systemImage)
                            .foregroundStyle(titleIconColor)
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.adaptiveTextPrimary(colorScheme))
                    Spacer()
                    Text(isExpanded ? "收起" : "展开")
                        .font(.caption)
                        .foregroundStyle(Theme.adaptiveTextSecondary(colorScheme))
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.adaptiveTextSecondary(colorScheme))
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
        .modifier(CollapsibleSectionCardSurfaceModifier(style: style))
    }

    private var titleIconColor: Color {
        switch style {
        case .standard:
            return Theme.brandPrimary(colorScheme)
        case .coach:
            return Theme.coachAccent(colorScheme)
        }
    }
}

private struct CollapsibleSectionCardSurfaceModifier: ViewModifier {
    let style: CollapsibleSectionCardStyle
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .padding()
            .background(cardBackground)
            .overlay {
                if style == .coach {
                    RoundedRectangle(cornerRadius: Theme.cornerRadiusCard, style: .continuous)
                        .strokeBorder(Theme.coachPromptBorder(colorScheme), lineWidth: 1)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadiusCard, style: .continuous))
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.25 : 0.06), radius: 8, y: 2)
    }

    private var cardBackground: some View {
        ZStack {
            Theme.cardBackground(colorScheme)
            if style == .coach {
                Theme.coachSectionSurface(colorScheme)
            }
        }
    }
}
