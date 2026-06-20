import SwiftUI

/// 热量剩余环形进度
/// @author jiali.qiu
struct CircularProgress: View {
    let remaining: Double
    let budget: Double
    let consumed: Double

    private var progress: Double {
        guard budget > 0 else { return 0 }
        return min(max(consumed / budget, 0), 1)
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Theme.primary.opacity(0.2), lineWidth: 14)

            Circle()
                .trim(from: 0, to: progress)
                .stroke(Theme.primary, style: StrokeStyle(lineWidth: 14, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.spring(duration: 0.6), value: progress)

            VStack(spacing: 4) {
                Text(remaining > 0 ? "剩余" : "超出")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                Text("\(Int(abs(remaining)))")
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.textPrimary)
                    .minimumScaleFactor(0.7)
                Text("大卡")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .frame(width: 180, height: 180)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("今日剩余 \(Int(remaining)) 大卡")
    }
}

#Preview {
    CircularProgress(remaining: 1234, budget: 1800, consumed: 566)
        .padding()
        .background(Theme.background)
}
