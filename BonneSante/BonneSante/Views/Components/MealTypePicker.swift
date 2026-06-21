import SwiftUI

/// 餐次选择器（录入页 / 确认页共用）
/// @author jiali.qiu
struct MealTypePicker: View {
    @Binding var selection: MealType
    var compact: Bool = false

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 8 : 10) {
            Text("餐次")
                .font(compact ? .caption.weight(.semibold) : .subheadline.weight(.semibold))
                .foregroundStyle(Theme.adaptiveTextSecondary(colorScheme))

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(MealType.allCases) { meal in
                        Button {
                            selection = meal
                        } label: {
                            Label(meal.label, systemImage: meal.icon)
                                .font(.caption.weight(.medium))
                                .padding(.horizontal, 12)
                                .padding(.vertical, compact ? 8 : 10)
                                .background(
                                    selection == meal
                                        ? Theme.brandPrimary(colorScheme)
                                        : Theme.cardBackground(colorScheme)
                                )
                                .foregroundStyle(
                                    selection == meal
                                        ? Theme.adaptiveTextPrimary(colorScheme)
                                        : Theme.adaptiveTextSecondary(colorScheme)
                                )
                                .overlay {
                                    if selection != meal {
                                        RoundedRectangle(cornerRadius: Theme.cornerRadiusButton)
                                            .strokeBorder(Theme.brandPrimary(colorScheme).opacity(0.25), lineWidth: 1)
                                    }
                                }
                                .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadiusButton))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

#Preview {
    MealTypePicker(selection: .constant(.lunch))
        .padding()
}
