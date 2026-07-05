import SwiftUI

/// AI 健身教练对话：快捷提示词、消息气泡与输入栏（莫兰迪灰绿主题）
/// @author jiali.qiu
struct CoachQuickPromptButton: View {
    let title: String
    var compact: Bool = false
    let action: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var isPressed = false

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
                .scaleEffect(isPressed ? 0.97 : 1)
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    withAnimation(Theme.Motion.buttonPress) { isPressed = true }
                }
                .onEnded { _ in
                    withAnimation(Theme.Motion.buttonPress) { isPressed = false }
                }
        )
    }
}

struct CoachMessageBubble: View {
    let text: String
    let isUser: Bool
    var compact: Bool = false

    @Environment(\.colorScheme) private var colorScheme

    private var cornerRadius: CGFloat { compact ? 12 : 14 }

    var body: some View {
        HStack(alignment: .top, spacing: compact ? 6 : 8) {
            if isUser { Spacer(minLength: compact ? 24 : 40) }

            if !isUser {
                Image(systemName: "figure.run")
                    .font(compact ? .caption2.weight(.semibold) : .caption.weight(.semibold))
                    .foregroundStyle(Theme.coachAccent(colorScheme))
                    .frame(width: compact ? 18 : 22, height: compact ? 18 : 22)
                    .background(Theme.coachPromptBackground(colorScheme))
                    .clipShape(Circle())
                    .padding(.top, 2)
            }

            Text(text)
                .font(compact ? .caption : .subheadline)
                .foregroundStyle(
                    isUser
                        ? Theme.coachUserBubbleForeground(colorScheme)
                        : Theme.coachAssistantBubbleForeground(colorScheme)
                )
                .padding(.horizontal, compact ? 10 : 12)
                .padding(.vertical, compact ? 8 : 10)
                .background(
                    isUser
                        ? Theme.coachUserBubbleBackground(colorScheme)
                        : Theme.coachAssistantBubbleBackground(colorScheme)
                )
                .overlay {
                    if !isUser {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .strokeBorder(Theme.coachAssistantBubbleBorder(colorScheme), lineWidth: 1)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))

            if !isUser { Spacer(minLength: compact ? 24 : 40) }
        }
    }
}

/// 教练对话底部输入栏
struct CoachChatInputBar: View {
    @Binding var text: String
    var placeholder: String = "问教练…"
    var isLoading: Bool = false
    var embedded: Bool = false
    var onSend: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    private var canSend: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isLoading
    }

    var body: some View {
        VStack(spacing: 0) {
            if !embedded {
                Divider()
                    .overlay(Theme.coachPromptBorder(colorScheme).opacity(0.35))
            }

            HStack(spacing: 10) {
                TextField(placeholder, text: $text, axis: .vertical)
                    .lineLimit(1...3)
                    .foregroundStyle(Theme.coachAssistantBubbleForeground(colorScheme))

                Button(action: onSend) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                        .foregroundStyle(
                            canSend
                                ? Theme.coachAccent(colorScheme)
                                : Theme.adaptiveTextTertiary(colorScheme)
                        )
                }
                .disabled(!canSend)
            }
            .padding(.horizontal, embedded ? 0 : 16)
            .padding(.vertical, embedded ? 4 : 12)
            .background(embedded ? Color.clear : Theme.coachInputBackground(colorScheme))
        }
    }
}
