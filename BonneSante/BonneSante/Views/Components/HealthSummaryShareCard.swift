import SwiftUI

/// 今日健康摘要分享图（ImageRenderer 渲染）
/// @author jiali.qiu
struct HealthSummaryShareCard: View {
    let dateLabel: String
    let phaseLabel: String
    let remainingCalories: Int
    let consumedCalories: Int
    let budgetCalories: Int
    let proteinGrams: Int
    let carbsGrams: Int
    let fatGrams: Int
    let checkupHint: String?
    let workoutHint: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Bonne-Santé")
                        .font(.title3.bold())
                    Text(dateLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(phaseLabel)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color(hex: 0xE5A5CF).opacity(0.25))
                    .clipShape(Capsule())
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(remainingCalories >= 0 ? "还可摄入" : "已超出")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(abs(remainingCalories))")
                        .fixedFont(size: 44, weight: .bold, design: .rounded)
                    Text("kcal")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                Text("预算 \(budgetCalories) · 已摄入 \(consumedCalories)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                macroTile(title: "蛋白", value: proteinGrams, unit: "g", color: Color(hex: 0x8FB4E8))
                macroTile(title: "碳水", value: carbsGrams, unit: "g", color: Color(hex: 0xD4C4A8))
                macroTile(title: "脂肪", value: fatGrams, unit: "g", color: Color(hex: 0xE5A5CF))
            }

            if let workoutHint, !workoutHint.isEmpty {
                insightRow(symbol: "figure.run", text: workoutHint)
            }
            if let checkupHint, !checkupHint.isEmpty {
                insightRow(symbol: "calendar.badge.clock", text: checkupHint)
            }

            Text("仅供参考，请遵医嘱。")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 4)
        }
        .padding(24)
        .frame(width: 360)
        .background(
            LinearGradient(
                colors: [Color(hex: 0xF9FBFF), Color(hex: 0xF3EFF8)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    private func macroTile(title: String, value: Int, unit: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(color)
            Text("\(value)\(unit)")
                .font(.subheadline.weight(.semibold))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(color.opacity(0.15))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func insightRow(symbol: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: symbol)
                .font(.caption)
                .foregroundStyle(Color(hex: 0x8FB4E8))
            Text(text)
                .font(.caption)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

enum HealthSummaryShareRenderer {
    @MainActor
    static func renderImage(from card: HealthSummaryShareCard) -> UIImage? {
        let renderer = ImageRenderer(content: card)
        renderer.scale = UIScreen.main.scale
        return renderer.uiImage
    }
}
