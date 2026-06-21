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
    static let textSecondaryDark = Color(hex: 0xB8B8BE)
    static let linkDark = Color(hex: 0x7EC8FF)

    // MARK: - Layout

    static let cornerRadiusCard: CGFloat = 16
    static let cornerRadiusButton: CGFloat = 12
    static let cornerRadiusInput: CGFloat = 10
    static let horizontalPadding: CGFloat = 20

    // MARK: - Adaptive

    static func pageBackground(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? backgroundDark : background
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

    /// 活动消耗 — 灰绿
    static func energyActive(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(hex: 0xA8C5A0) : Color(hex: 0x9BB89A)
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

    static func phaseAccent(_ phase: CyclePhase, _ scheme: ColorScheme) -> Color {
        Color(hex: phase.themeColorHex)
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
            .opacity(configuration.isPressed ? 0.82 : 1)
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
