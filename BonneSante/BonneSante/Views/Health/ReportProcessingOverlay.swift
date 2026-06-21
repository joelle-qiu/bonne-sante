import SwiftUI

/// 报告导入 / 校对入库进度回调（主线程）
typealias ReportImportProgressHandler = @MainActor (Double, String) -> Void

/// 解析与入库时的全屏进度遮罩
/// @author jiali.qiu
struct ReportProcessingOverlay: View {
    let message: String
    var progress: Double

    private var clampedProgress: Double {
        min(1, max(0.04, progress))
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.32)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                ProgressView()
                    .controlSize(.large)
                    .tint(Theme.primaryDark)

                ProgressView(value: clampedProgress)
                    .progressViewStyle(.linear)
                    .tint(Theme.primaryDark)
                    .frame(maxWidth: 220)

                Text("\(Int(clampedProgress * 100))%")
                    .font(.caption.monospacedDigit().weight(.medium))
                    .foregroundStyle(Theme.textSecondary)

                Text(message)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.textPrimary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 260)

                Text("数据仅在本地处理，大文件可能需要十几秒")
                    .font(.caption2)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 26)
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadiusCard))
            .shadow(color: .black.opacity(0.12), radius: 16, y: 6)
        }
        .transition(.opacity.combined(with: .scale(scale: 0.96)))
        .animation(.easeInOut(duration: 0.2), value: message)
        .animation(.easeInOut(duration: 0.25), value: progress)
    }
}

/// 导入流程进度上报（服务层调用）
enum ReportImportProgressReporter {
    static func emit(
        _ handler: ReportImportProgressHandler?,
        _ fraction: Double,
        _ message: String
    ) async {
        guard let handler else { return }
        await handler(fraction, message)
    }
}
