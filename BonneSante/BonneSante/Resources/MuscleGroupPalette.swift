import SwiftUI

/// 训练部位莫兰迪配色（动作卡片 / 候选卡片）
/// @author jiali.qiu
enum MuscleGroupPalette {

    enum Region: String, CaseIterable {
        case back = "背"
        case chest = "胸"
        case legs = "腿"
        case glutes = "臀"
        case shoulders = "肩"
        case core = "核心"
        case cardio = "有氧"
        case fullBody = "全身"
        case other = "其他"
    }

    static func region(for muscleGroup: String) -> Region {
        let text = muscleGroup.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { return .other }
        if text.contains("背") { return .back }
        if text.contains("胸") { return .chest }
        if text.contains("肩") { return .shoulders }
        if text.contains("核心") || text.contains("腹") { return .core }
        if text.contains("有氧") || text.contains("心肺") { return .cardio }
        if text.contains("全身") { return .fullBody }
        if text.contains("臀") { return .glutes }
        if text.contains("腿") || text.contains("下肢") { return .legs }
        return .other
    }

    static func color(for muscleGroup: String, scheme: ColorScheme) -> Color {
        color(for: region(for: muscleGroup), scheme: scheme)
    }

    static func color(for region: Region, scheme: ColorScheme) -> Color {
        switch region {
        case .back:
            return scheme == .dark ? Color(hex: 0x8FB4E8) : Color(hex: 0x8FB4E8)
        case .chest:
            return scheme == .dark ? Color(hex: 0xE0C0A8) : Color(hex: 0xE0C0A8)
        case .legs, .glutes:
            return scheme == .dark ? Color(hex: 0xA8C5A0) : Color(hex: 0x9BB89A)
        case .shoulders:
            return scheme == .dark ? Color(hex: 0xC9B8E8) : Color(hex: 0xC9B8E8)
        case .core:
            return scheme == .dark ? Color(hex: 0xE8A8D0) : Color(hex: 0xE5A5CF)
        case .cardio:
            return scheme == .dark ? Color(hex: 0xA8D4C4) : Color(hex: 0x9ECAB8)
        case .fullBody:
            return scheme == .dark ? Color(hex: 0xB8C8E8) : Color(hex: 0xADC8F5)
        case .other:
            return Theme.adaptiveTextSecondary(scheme)
        }
    }

    static func label(for muscleGroup: String) -> String {
        let region = region(for: muscleGroup)
        if region == .other, !muscleGroup.isEmpty { return muscleGroup }
        return region.rawValue
    }
}

/// 部位色条 + 胶囊标签
struct MuscleGroupBadge: View {
    let muscleGroup: String
    @Environment(\.colorScheme) private var colorScheme

    private var tint: Color {
        MuscleGroupPalette.color(for: muscleGroup, scheme: colorScheme)
    }

    var body: some View {
        Text(MuscleGroupPalette.label(for: muscleGroup))
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .foregroundStyle(tint)
            .background(tint.opacity(colorScheme == .dark ? 0.22 : 0.28))
            .clipShape(Capsule())
    }
}
