import SwiftUI

struct NutritionCard: View {
    let title: String
    let value: String
    let unit: String
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(value)
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundStyle(color)

            Text(unit)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(color.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

#Preview {
    HStack {
        NutritionCard(title: "Calories", value: "450", unit: "kcal", color: .orange)
        NutritionCard(title: "Protein", value: "25.5", unit: "g", color: .red)
        NutritionCard(title: "Carbs", value: "60.0", unit: "g", color: .blue)
        NutritionCard(title: "Fat", value: "15.2", unit: "g", color: .yellow)
    }
    .padding()
}
