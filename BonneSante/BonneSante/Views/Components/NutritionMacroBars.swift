import SwiftUI

/// 今日营养条形可视化（莫兰迪配色）
/// @author jiali.qiu
struct NutritionMacroBars: View {
    let protein: Double
    let carbs: Double
    let fat: Double
    let calories: Double

    @Environment(\.colorScheme) private var colorScheme

    private var maxMacro: Double {
        max(protein, carbs, fat, 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("今日营养")
                    .font(.headline)
                    .foregroundStyle(Theme.adaptiveTextPrimary(colorScheme))
                Spacer()
                Text("\(Int(calories).formatted()) 大卡")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.adaptiveTextSecondary(colorScheme))
            }

            macroRow(title: "蛋白质", value: protein, unit: "g", color: Theme.macroProtein(colorScheme), icon: "bolt.fill")
            macroRow(title: "碳水", value: carbs, unit: "g", color: Theme.macroCarbs(colorScheme), icon: "leaf.fill")
            macroRow(title: "脂肪", value: fat, unit: "g", color: Theme.macroFat(colorScheme), icon: "drop.fill")
        }
        .morandiCard()
    }

    private func macroRow(title: String, value: Double, unit: String, color: Color, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label(title, systemImage: icon)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(color)
                Spacer()
                Text("\(formatMacro(value))\(unit)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.adaptiveTextPrimary(colorScheme))
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(color.opacity(colorScheme == .dark ? 0.18 : 0.24))
                    Capsule()
                        .fill(color)
                        .frame(width: geo.size.width * CGFloat(min(value / maxMacro, 1)))
                        .animation(.spring(duration: 0.45), value: value)
                }
            }
            .frame(height: 8)
        }
    }

    private func formatMacro(_ value: Double) -> String {
        value >= 10 ? "\(Int(value))" : String(format: "%.1f", value)
    }
}

#Preview("浅色") {
    NutritionMacroBars(protein: 42, carbs: 120, fat: 35, calories: 980)
        .padding()
        .background(Theme.background)
        .preferredColorScheme(.light)
}

#Preview("深色") {
    NutritionMacroBars(protein: 42, carbs: 120, fat: 35, calories: 980)
        .padding()
        .background(Theme.backgroundDark)
        .preferredColorScheme(.dark)
}
