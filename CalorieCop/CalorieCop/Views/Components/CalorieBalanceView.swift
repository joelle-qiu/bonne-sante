import SwiftUI

struct CalorieBalanceView: View {
    let consumed: Double
    let burned: Double
    var targetDeficit: Double? = nil  // The planned daily calorie deficit to reach weight goal

    var balance: Double {
        burned - consumed
    }

    var isDeficit: Bool {
        balance > 0
    }

    // 还能吃 = 消耗 - 目标缺口 - 已摄入
    // This dynamically changes based on actual vs estimated burned calories
    var remaining: Double? {
        guard let deficit = targetDeficit else { return nil }
        return burned - deficit - consumed
    }

    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 8) {
                VStack(spacing: 4) {
                    Image(systemName: "fork.knife")
                        .font(.title2)
                        .foregroundStyle(.orange)
                    Text(consumed.formattedCalories)
                        .font(.title)
                        .fontWeight(.bold)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Text("摄入")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(minWidth: 70)

                Image(systemName: "minus")
                    .font(.headline)
                    .foregroundStyle(.secondary)

                VStack(spacing: 4) {
                    Image(systemName: "flame.fill")
                        .font(.title2)
                        .foregroundStyle(.red)
                    Text(burned.formattedCalories)
                        .font(.title)
                        .fontWeight(.bold)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Text("消耗")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(minWidth: 70)

                Image(systemName: "equal")
                    .font(.headline)
                    .foregroundStyle(.secondary)

                VStack(spacing: 4) {
                    Image(systemName: isDeficit ? "arrow.down.circle.fill" : "arrow.up.circle.fill")
                        .font(.title2)
                        .foregroundStyle(isDeficit ? .green : .red)
                    Text(abs(balance).formattedCalories)
                        .font(.title)
                        .fontWeight(.bold)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .foregroundStyle(isDeficit ? .green : .red)
                    Text(isDeficit ? "缺口" : "盈余")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(minWidth: 70)
            }

            // Show remaining calories based on target deficit
            if let remaining = remaining, let deficit = targetDeficit {
                Divider()

                HStack {
                    if remaining > 0 {
                        Label("还可吃 \(Int(remaining)) kcal", systemImage: "checkmark.circle.fill")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundStyle(.green)
                    } else {
                        Label("已超出 \(Int(-remaining)) kcal", systemImage: "exclamationmark.triangle.fill")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundStyle(.red)
                    }

                    Spacer()

                    Text("目标缺口 \(Int(deficit)) kcal")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.1), radius: 5, x: 0, y: 2)
    }
}

#Preview {
    VStack(spacing: 20) {
        CalorieBalanceView(consumed: 1200, burned: 2000)
        CalorieBalanceView(consumed: 2500, burned: 2000)
    }
    .padding()
    .background(Color(.systemGroupedBackground))
}
