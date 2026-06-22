import SwiftUI

/// API 密钥设置（兼容旧入口，内部使用 AISettingsView）
struct APIKeySetupView: View {
    @Environment(\.dismiss) private var dismiss

    var onComplete: (() -> Void)?

    var body: some View {
        NavigationStack {
            AISettingsView(onComplete: {
                onComplete?()
                dismiss()
            })
            .cycleThemedPageBackground()
            .navigationTitle("API 设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Compact API Key Prompt View

struct APIKeyPromptView: View {
    let onSetup: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "key.fill")
                .font(.largeTitle)
                .foregroundStyle(.orange)

            Text("需要设置 API 密钥")
                .font(.headline)

            Text("使用 AI 来识别食物。请先设置 DeepSeek API 密钥以启用文字解析功能。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button(action: onSetup) {
                HStack {
                    Image(systemName: "gear")
                    Text("设置 API 密钥")
                }
                .padding()
                .frame(maxWidth: .infinity)
                .background(Color.blue)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.1), radius: 10)
        .padding()
    }
}

#Preview {
    APIKeySetupView()
}
