import SwiftUI

/// 长辈版：全局大字与触控优化
/// @author jiali.qiu
enum ElderModeMetrics {
    /// 动态字号（accessibility2 比 accessibility3 更易排版）
    static let dynamicTypeSize: DynamicTypeSize = .accessibility2
    /// 固定 pt 字号仅微调，避免与 dynamicType 双重放大
    static let fixedFontScale: CGFloat = 1.08
    /// ScrollView 底部留白，避免 TabBar 遮挡
    static let scrollBottomInset: CGFloat = 56
}

private struct ElderModeEnabledKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var elderModeEnabled: Bool {
        get { self[ElderModeEnabledKey.self] }
        set { self[ElderModeEnabledKey.self] = newValue }
    }
}

/// 根视图注入长辈版环境与大字号
struct ElderModeRootModifier: ViewModifier {
    let enabled: Bool

    func body(content: Content) -> some View {
        Group {
            if enabled {
                content
                    .environment(\.elderModeEnabled, true)
                    .dynamicTypeSize(ElderModeMetrics.dynamicTypeSize)
            } else {
                content
                    .environment(\.elderModeEnabled, false)
            }
        }
    }
}

extension View {
    func elderModeRoot(enabled: Bool) -> some View {
        modifier(ElderModeRootModifier(enabled: enabled))
    }

    /// 列表/仪表盘 ScrollView 底部留白（长辈版 TabBar 不挡内容）
    func elderModeScrollBottomInset() -> some View {
        modifier(ElderModeScrollBottomInsetModifier())
    }

    /// 固定 pt 字号在长辈版下轻微放大
    func fixedFont(
        size: CGFloat,
        weight: Font.Weight = .regular,
        design: Font.Design = .default
    ) -> some View {
        modifier(FixedFontModifier(baseSize: size, weight: weight, design: design))
    }
}

private struct ElderModeScrollBottomInsetModifier: ViewModifier {
    @Environment(\.elderModeEnabled) private var elderModeEnabled

    func body(content: Content) -> some View {
        content.safeAreaPadding(.bottom, elderModeEnabled ? ElderModeMetrics.scrollBottomInset : 0)
    }
}

private struct FixedFontModifier: ViewModifier {
    @Environment(\.elderModeEnabled) private var elderModeEnabled

    let baseSize: CGFloat
    let weight: Font.Weight
    let design: Font.Design

    func body(content: Content) -> some View {
        let size = elderModeEnabled ? baseSize * ElderModeMetrics.fixedFontScale : baseSize
        content.font(.system(size: size, weight: weight, design: design))
    }
}
