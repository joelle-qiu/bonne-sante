import SwiftUI

/// Bonne-Santé 莫兰迪设计 Token
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

    static let primaryDark = Color(hex: 0x7A9AD4)
    static let backgroundDark = Color(hex: 0x1A1A1E)
    static let accentDark = Color(hex: 0xC88BB5)
    static let cardDark = Color(hex: 0x2A2A30)

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
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadiusCard))
    }
}

extension View {
    func morandiCard() -> some View {
        modifier(MorandiCardModifier())
    }
}
