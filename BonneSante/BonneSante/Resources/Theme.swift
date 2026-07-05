import SwiftUI

/// Bonne-Santé 莫兰迪设计 Token（浅色 / 深色自适应）
/// @author jiali.qiu
enum Theme {
    // MARK: - Brand Colors (Light)

    static let primary = Color(hex: 0xADC8F5)
    static let background = Color(hex: 0xF9FBFF)
    static let accent = Color(hex: 0xE5A5CF)
    static let warning = Color(hex: 0xE8A0A0)
    static let textPrimary = Color(hex: 0x1C1C1E)
    static let textSecondary = Color(hex: 0x6E6E73)

    // MARK: - Brand Colors (Dark)

    static let primaryDark = Color(hex: 0x8FB4E8)
    static let backgroundDark = Color(hex: 0x121214)
    static let accentDark = Color(hex: 0xE8A8D0)
    static let warningDark = Color(hex: 0xFF9E9E)
    static let cardDark = Color(hex: 0x2C2C30)
    static let textPrimaryDark = Color(hex: 0xF5F5F7)
    static let textSecondaryDark = Color(hex: 0xD1D1D6)
    static let linkDark = Color(hex: 0x7EC8FF)

    // MARK: - Layout

    static let cornerRadiusCard: CGFloat = 16
    static let cornerRadiusButton: CGFloat = 12
    static let cornerRadiusInput: CGFloat = 10
    static let horizontalPadding: CGFloat = 20

    // MARK: - Motion（PRD §11.4 P2）

    enum Motion {
        static let cardSpring = Animation.spring(duration: 0.35, bounce: 0.22)
        static let progressSpring = Animation.spring(duration: 0.6, bounce: 0.18)
        static let phaseTransition = Animation.easeInOut(duration: 0.4)
        static let buttonPress = Animation.easeOut(duration: 0.18)
    }

    // MARK: - Adaptive

    static func pageBackground(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? backgroundDark : background
    }

    /// 周期主题页背景染色强度（未知阶段为 0）
    static func phasePageTintOpacity(_ phase: CyclePhase, _ scheme: ColorScheme) -> Double {
        guard phase != .unknown else { return 0 }
        switch phase {
        case .follicular:
            return scheme == .dark ? 0.11 : 0.09
        default:
            return scheme == .dark ? 0.10 : 0.12
        }
    }

    static func phasePageGradientOpacity(_ phase: CyclePhase, _ scheme: ColorScheme) -> Double {
        guard phase != .unknown else { return 0 }
        switch phase {
        case .follicular:
            return scheme == .dark ? 0.15 : 0.14
        default:
            return scheme == .dark ? 0.14 : 0.18
        }
    }

    static func brandPrimary(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? primaryDark : primary
    }

    static func adaptiveTextPrimary(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? textPrimaryDark : textPrimary
    }

    static func adaptiveTextSecondary(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? textSecondaryDark : textSecondary
    }

    static func adaptiveTextTertiary(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(hex: 0xAEAEB4) : Color(hex: 0x8E8E93)
    }

    static func adaptiveWarning(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? warningDark : warning
    }

    static func adaptiveAccent(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? accentDark : accent
    }

    static func cardBackground(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? cardDark : Color.white.opacity(0.92)
    }

    static func departmentLabel(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(hex: 0x9FD4FF) : primaryDark
    }

    // MARK: - 数据可视化（莫兰迪语义色）

    /// 活动消耗 — 灰绿（与卵泡期主题同色系）
    static func energyActive(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(hex: 0x8FAF94) : Color(hex: 0x6B9074)
    }

    /// 基础代谢 — 温柔蓝
    static func energyBasal(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? primaryDark : Color(hex: 0x8FB4E8)
    }

    /// 已摄入 — 暖杏
    static func energyConsumed(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(hex: 0xE5C4A0) : Color(hex: 0xE0C0A8)
    }

    /// 蛋白质 — 雾蓝
    static func macroProtein(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(hex: 0x9FC0E8) : Color(hex: 0x8FB4E8)
    }

    /// 碳水 — 燕麦
    static func macroCarbs(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(hex: 0xD9C9A8) : Color(hex: 0xD4C4A8)
    }

    /// 脂肪 — 粉紫
    static func macroFat(_ scheme: ColorScheme) -> Color {
        adaptiveAccent(scheme)
    }

    /// 周期阶段强调色（莫兰迪：深 sage / 灰玫瑰 / 雾紫，深浅色自适应）
    static func phaseAccent(_ phase: CyclePhase, _ scheme: ColorScheme) -> Color {
        switch phase {
        case .menstrual:
            return scheme == .dark ? Color(hex: 0xD4A5A5) : Color(hex: 0xB07878)
        case .follicular:
            return scheme == .dark ? Color(hex: 0x8FAF94) : Color(hex: 0x5E8266)
        case .luteal:
            return scheme == .dark ? Color(hex: 0xB5A8CC) : Color(hex: 0x8A7BA8)
        case .unknown:
            return scheme == .dark ? Color(hex: 0xAEAEB4) : Color(hex: 0xC8C8CD)
        }
    }

    /// 周期条背景（仅作用于 PhaseBar / tips 边框，不整页染色）
    static func phaseBarBackground(_ phase: CyclePhase, _ scheme: ColorScheme) -> Color {
        let base = phaseAccent(phase, scheme)
        return base.opacity(scheme == .dark ? 0.16 : 0.28)
    }

    static func phaseBarBorder(_ phase: CyclePhase, _ scheme: ColorScheme) -> Color {
        phaseAccent(phase, scheme).opacity(scheme == .dark ? 0.55 : 0.65)
    }

    static func link(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? linkDark : Color(hex: 0x6B8FC7)
    }

    // MARK: - AI 教练对话

    /// 快捷提示词胶囊背景
    static func coachPromptBackground(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? cardDark : Color.white.opacity(0.96)
    }

    /// 快捷提示词文字（高对比）
    static func coachPromptForeground(_ scheme: ColorScheme) -> Color {
        adaptiveTextPrimary(scheme)
    }

    /// 快捷提示词描边
    static func coachPromptBorder(_ scheme: ColorScheme) -> Color {
        brandPrimary(scheme).opacity(scheme == .dark ? 0.62 : 0.52)
    }

    /// 用户气泡背景
    static func coachUserBubbleBackground(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? brandPrimary(scheme).opacity(0.45) : Color(hex: 0x8FB4E8).opacity(0.58)
    }

    /// 助手气泡背景
    static func coachAssistantBubbleBackground(_ scheme: ColorScheme) -> Color {
        coachPromptBackground(scheme)
    }

    /// 助手气泡描边
    static func coachAssistantBubbleBorder(_ scheme: ColorScheme) -> Color {
        adaptiveTextTertiary(scheme).opacity(scheme == .dark ? 0.35 : 0.28)
    }
}

// MARK: - Color Hex

extension Color {
    init(hex: UInt, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}

// MARK: - Card Modifier

struct MorandiCardModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .padding()
            .background(Theme.cardBackground(colorScheme))
            .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadiusCard))
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.25 : 0.06), radius: 8, y: 2)
    }
}

extension View {
    func morandiCard() -> some View {
        modifier(MorandiCardModifier())
    }

    /// 卡片入场微动效（首页洞察条等）
    func morandiCardAppear(delay: Double = 0) -> some View {
        modifier(MorandiCardAppearModifier(delay: delay))
    }

    /// Form / List 在周期主题页上的统一行背景与文字对比度
    func morandiFormSurface() -> some View {
        modifier(MorandiFormSurfaceModifier())
    }
}

private struct MorandiCardAppearModifier: ViewModifier {
    let delay: Double
    @State private var visible = false

    func body(content: Content) -> some View {
        content
            .opacity(visible ? 1 : 0)
            .offset(y: visible ? 0 : 8)
            .onAppear {
                withAnimation(Theme.Motion.cardSpring.delay(delay)) {
                    visible = true
                }
            }
    }
}

private struct MorandiFormSurfaceModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .scrollContentBackground(.hidden)
            .listRowBackground(Theme.cardBackground(colorScheme))
            .foregroundStyle(Theme.adaptiveTextPrimary(colorScheme))
    }
}

// MARK: - Quick Action Button

/// 首页快捷操作统一按钮样式（主操作实心 / 次操作描边）
/// @author jiali.qiu
struct MorandiQuickActionButtonStyle: ButtonStyle {
    enum Variant {
        case primary
        case secondary
    }

    let variant: Variant
    @Environment(\.colorScheme) private var colorScheme

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(background)
            .foregroundStyle(foreground)
            .overlay {
                if variant == .secondary {
                    RoundedRectangle(cornerRadius: Theme.cornerRadiusButton)
                        .strokeBorder(Theme.brandPrimary(colorScheme).opacity(colorScheme == .dark ? 0.65 : 0.55), lineWidth: 1.5)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadiusButton))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(Theme.Motion.buttonPress, value: configuration.isPressed)
            .opacity(configuration.isPressed ? 0.88 : 1)
    }

    private var background: Color {
        switch variant {
        case .primary:
            return Theme.brandPrimary(colorScheme)
        case .secondary:
            return Theme.cardBackground(colorScheme).opacity(colorScheme == .dark ? 0.55 : 0.85)
        }
    }

    private var foreground: Color {
        switch variant {
        case .primary:
            return colorScheme == .dark ? Theme.textPrimaryDark : Theme.textPrimary
        case .secondary:
            return Theme.adaptiveTextPrimary(colorScheme)
        }
    }
}

// MARK: - Cycle Themed Page Background

/// 全局周期主题背景：基底色 + 阶段色温和晕染（经 `@Environment(\.cyclePhase)` 驱动）
struct CycleThemedBackground: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.cyclePhase) private var cyclePhase

    var body: some View {
        ZStack {
            Theme.pageBackground(colorScheme)

            if cyclePhase != .unknown {
                Theme.phaseAccent(cyclePhase, colorScheme)
                    .opacity(Theme.phasePageTintOpacity(cyclePhase, colorScheme))

                LinearGradient(
                    colors: [
                        Theme.phaseAccent(cyclePhase, colorScheme)
                            .opacity(Theme.phasePageGradientOpacity(cyclePhase, colorScheme)),
                        Theme.pageBackground(colorScheme).opacity(0)
                    ],
                    startPoint: .top,
                    endPoint: UnitPoint(x: 0.5, y: 0.38)
                )
            }
        }
        .animation(.easeInOut(duration: 0.4), value: cyclePhase)
    }
}

extension View {
    /// 应用周期联动页背景（替代 `Theme.pageBackground`）
    func cycleThemedPageBackground() -> some View {
        background {
            CycleThemedBackground()
                .ignoresSafeArea()
        }
    }
}
