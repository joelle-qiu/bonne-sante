import SwiftUI

/// AI 教练对话：快捷提示词与消息气泡（高对比、深浅色自适应）
/// @author jiali.qiu
struct CoachQuickPromptButton: View {
    let title: String
    var compact: Bool = false
    let action: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(compact ? .caption.weight(.medium) : .caption.weight(.semibold))
                .foregroundStyle(Theme.coachPromptForeground(colorScheme))
                .multilineTextAlignment(.leading)
                .padding(.horizontal, compact ? 10 : 12)
                .padding(.vertical, compact ? 6 : 8)
                .background(Theme.coachPromptBackground(colorScheme))
                .overlay {
                    Capsule()
                        .strokeBorder(Theme.coachPromptBorder(colorScheme), lineWidth: 1)
                }
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

struct CoachMessageBubble: View {
    let text: String
    let isUser: Bool
    var compact: Bool = false

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack {
            if isUser { Spacer(minLength: compact ? 24 : 40) }
            Text(text)
                .font(compact ? .caption : .subheadline)
                .foregroundStyle(Theme.coachPromptForeground(colorScheme))
                .padding(.horizontal, compact ? 10 : 12)
                .padding(.vertical, compact ? 8 : 10)
                .background(
                    isUser
                        ? Theme.coachUserBubbleBackground(colorScheme)
                        : Theme.coachAssistantBubbleBackground(colorScheme)
                )
                .overlay {
                    if !isUser {
                        RoundedRectangle(cornerRadius: compact ? 12 : 14)
                            .strokeBorder(Theme.coachAssistantBubbleBorder(colorScheme), lineWidth: 1)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: compact ? 12 : 14))
            if !isUser { Spacer(minLength: compact ? 24 : 40) }
        }
    }
}
