import SwiftUI

/// 首页横向洞察卡片（训练 / 复查 / 风险 / 周期）
/// @author jiali.qiu
struct HomeInsightCarousel: View {
    struct Item: Identifiable {
        let id: String
        let symbol: String
        let tint: Color
        let title: String
        let subtitle: String
    }

    let items: [Item]

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("今日洞察")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.adaptiveTextPrimary(colorScheme))

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        card(item)
                            .morandiCardAppear(delay: Double(index) * 0.05)
                    }
                }
                .padding(.horizontal, 2)
                .padding(.vertical, 2)
            }
        }
    }

    private func card(_ item: Item) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: item.symbol)
                .font(.title3)
                .foregroundStyle(item.tint)
            Text(item.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.adaptiveTextPrimary(colorScheme))
                .lineLimit(2)
            Text(item.subtitle)
                .font(.caption)
                .foregroundStyle(Theme.adaptiveTextSecondary(colorScheme))
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(width: 168, alignment: .leading)
        .padding(14)
        .background(Theme.cardBackground(colorScheme))
        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadiusCard))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cornerRadiusCard)
                .strokeBorder(item.tint.opacity(0.35), lineWidth: 1)
        )
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.2 : 0.05), radius: 6, y: 2)
    }
}
