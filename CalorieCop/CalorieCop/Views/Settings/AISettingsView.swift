import SwiftUI

/// AI 服务配置（Keychain 存储 + 状态灯 + 连接测试）
/// @author jiali.qiu
struct AISettingsView: View {
    var embeddedMode: Bool = false
    var onComplete: (() -> Void)?

    @State private var deepSeekKey = ""
    @State private var qwenKey = ""
    @State private var showDeepSeekKey = false
    @State private var showQwenKey = false
    @State private var selectedRegion: APIRegion = .international
    @State private var refreshTrigger = false
    @State private var isTestingDeepSeek = false
    @State private var deepSeekTestResult: APIValidationResult?
    @State private var saveErrorMessage: String?

    private var status: AIServiceStatus {
        let _ = refreshTrigger
        return AIServiceStatus.current
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if !embeddedMode {
                    headerSection
                }

                statusSection

                regionSection

                apiKeySection(
                    title: "DeepSeek API",
                    subtitle: "文字解析与 AI 顾问（必填）",
                    key: $deepSeekKey,
                    showKey: $showDeepSeekKey,
                    isConfigured: status.isDeepSeekReady,
                    hasUserKey: APIKeyManager.hasUserDeepSeekKey,
                    instructions: deepSeekInstructions,
                    websiteURL: "https://platform.deepseek.com",
                    testAction: testDeepSeekConnection,
                    isTesting: isTestingDeepSeek,
                    testResult: deepSeekTestResult
                )

                apiKeySection(
                    title: "阿里云 Qwen API（可选）",
                    subtitle: "拍照识食",
                    key: $qwenKey,
                    showKey: $showQwenKey,
                    isConfigured: status.isQwenReady,
                    hasUserKey: APIKeyManager.hasUserQwenKey,
                    instructions: qwenInstructions,
                    websiteURL: qwenWebsiteURL,
                    testAction: nil,
                    isTesting: false,
                    testResult: nil
                )

                if let saveErrorMessage {
                    Text(saveErrorMessage)
                        .font(.caption)
                        .foregroundStyle(Theme.warning)
                }

                Button(action: saveKeys) {
                    Text("保存设置")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(canSave ? Theme.primary : Color.gray)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadiusButton))
                }
                .disabled(!canSave)

                securityNote

                if APIKeyManager.hasUserDeepSeekKey || APIKeyManager.hasUserQwenKey {
                    Button(role: .destructive, action: clearKeys) {
                        HStack {
                            Image(systemName: "trash")
                            Text("清除已保存的密钥")
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Theme.warning.opacity(0.12))
                        .foregroundStyle(Theme.warning)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadiusButton))
                    }
                }

                developerKeyHints
            }
            .padding()
        }
        .scrollDismissesKeyboard(.interactively)
        .onAppear {
            selectedRegion = APIKeyManager.region
        }
    }

    // MARK: - Sections

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("AI 服务配置")
                .font(.title2.bold())
            Text("密钥仅保存在本机 Keychain，不会上传服务器。")
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
        }
    }

    private var statusSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("服务状态")
                .font(.headline)

            statusRow(
                title: "DeepSeek",
                subtitle: "文字录入 / AI 顾问",
                isReady: status.isDeepSeekReady
            )
            statusRow(
                title: "Qwen VL",
                subtitle: "拍照识食",
                isReady: status.isQwenReady
            )
        }
        .padding()
        .morandiCard()
    }

    private func statusRow(title: String, subtitle: String, isReady: Bool) -> some View {
        HStack(spacing: 12) {
            Circle()
                .fill(isReady ? Color.green : Color.orange)
                .frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            Text(isReady ? "已就绪" : "未配置")
                .font(.caption)
                .foregroundStyle(isReady ? .green : .orange)
        }
    }

    private var regionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "globe")
                    .foregroundStyle(Theme.primary)
                Text("Qwen 识图地区")
                    .font(.headline)
            }
            Text("仅影响拍照识食的 Qwen 服务器地址。")
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
            Picker("地区", selection: $selectedRegion) {
                ForEach(APIRegion.allCases, id: \.self) { region in
                    Text(region.displayName).tag(region)
                }
            }
            .pickerStyle(.segmented)
        }
        .padding()
        .morandiCard()
    }

    private var securityNote: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "lock.shield")
                .foregroundStyle(.green)
            Text("API 密钥使用 iOS Keychain 加密存储，仅在本设备可用。")
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
        }
        .padding()
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadiusInput))
    }

    @ViewBuilder
    private var developerKeyHints: some View {
        let _ = refreshTrigger
        if !APIKeyManager.hasUserDeepSeekKey && APIKeyManager.isDeepSeekConfigured {
            hintBanner("DeepSeek 正在使用开发者预设密钥")
        }
        if !APIKeyManager.hasUserQwenKey && APIKeyManager.isQwenConfigured {
            hintBanner("Qwen 正在使用开发者预设密钥")
        }
    }

    private func hintBanner(_ text: String) -> some View {
        HStack {
            Image(systemName: "info.circle")
            Text(text)
                .font(.caption)
        }
        .foregroundStyle(Theme.textSecondary)
        .padding()
        .background(Theme.primary.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadiusInput))
    }

    // MARK: - API Key Section

    private func apiKeySection(
        title: String,
        subtitle: String,
        key: Binding<String>,
        showKey: Binding<Bool>,
        isConfigured: Bool,
        hasUserKey: Bool,
        instructions: [String],
        websiteURL: String,
        testAction: (() -> Void)?,
        isTesting: Bool,
        testResult: APIValidationResult?
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer()
                configurationBadge(isConfigured: isConfigured, hasUserKey: hasUserKey)
            }

            VStack(alignment: .leading, spacing: 4) {
                ForEach(instructions, id: \.self) { step in
                    Text(step)
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
                Link(destination: URL(string: websiteURL)!) {
                    Label("打开官网", systemImage: "arrow.up.right.square")
                        .font(.caption)
                }
            }
            .padding()
            .background(Color(.systemGray6))
            .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadiusInput))

            keyInputField(key: key, showKey: showKey)

            if let testAction {
                HStack {
                    Button(action: testAction) {
                        HStack {
                            if isTesting {
                                ProgressView().controlSize(.small)
                            }
                            Text(isTesting ? "测试中…" : "测试 DeepSeek 连接")
                        }
                        .font(.caption)
                    }
                    .disabled(isTesting || (!hasUserKey && key.wrappedValue.isEmpty && !isConfigured))

                    if let testResult {
                        Text(testResult.message)
                            .font(.caption)
                            .foregroundStyle(testResult.isSuccess ? .green : Theme.warning)
                    }
                }
            }
        }
        .padding()
        .morandiCard()
    }

    private func configurationBadge(isConfigured: Bool, hasUserKey: Bool) -> some View {
        Group {
            if hasUserKey {
                Label("Keychain", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else if isConfigured {
                Label("开发者预设", systemImage: "wrench.fill")
                    .foregroundStyle(.blue)
            } else {
                Label("未配置", systemImage: "xmark.circle")
                    .foregroundStyle(.orange)
            }
        }
        .font(.caption)
    }

    private func keyInputField(key: Binding<String>, showKey: Binding<Bool>) -> some View {
        HStack {
            Group {
                if showKey.wrappedValue {
                    TextField("输入 API Key", text: key)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } else {
                    SecureField("输入 API Key", text: key)
                }
            }
            .textFieldStyle(.plain)

            Button {
                if let clipboard = UIPasteboard.general.string {
                    key.wrappedValue = clipboard
                }
            } label: {
                Image(systemName: "doc.on.clipboard")
                    .foregroundStyle(Theme.primary)
            }

            if !key.wrappedValue.isEmpty {
                Button { key.wrappedValue = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Theme.textSecondary)
                }
            }

            Button { showKey.wrappedValue.toggle() } label: {
                Image(systemName: showKey.wrappedValue ? "eye.slash" : "eye")
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadiusInput))
    }

    // MARK: - Actions

    private var canSave: Bool {
        let regionChanged = selectedRegion != APIKeyManager.region
        return regionChanged || !deepSeekKey.isEmpty || !qwenKey.isEmpty
    }

    private var deepSeekInstructions: [String] {
        [
            "1. 访问 platform.deepseek.com 注册",
            "2. 控制台 → API Keys 创建密钥",
            "3. 复制并粘贴到下方"
        ]
    }

    private var qwenInstructions: [String] {
        switch selectedRegion {
        case .international:
            return [
                "1. 访问阿里云国际站 DashScope",
                "2. API-KEY 管理创建密钥",
                "3. 复制并粘贴到下方"
            ]
        case .china:
            return [
                "1. 访问阿里云 DashScope",
                "2. API-KEY 管理创建密钥",
                "3. 复制并粘贴到下方"
            ]
        }
    }

    private var qwenWebsiteURL: String {
        selectedRegion == .international
            ? "https://www.alibabacloud.com/product/dashscope"
            : "https://dashscope.console.aliyun.com"
    }

    private func testDeepSeekConnection() {
        let keyToTest: String
        if !deepSeekKey.isEmpty {
            keyToTest = deepSeekKey
        } else if APIKeyManager.hasUserDeepSeekKey, let existing = APIKeyManager.deepSeekAPIKey {
            keyToTest = existing
        } else if let dev = APIKeyManager.deepSeekAPIKey {
            keyToTest = dev
        } else {
            deepSeekTestResult = .invalidKey
            return
        }

        isTestingDeepSeek = true
        deepSeekTestResult = nil
        Task {
            let result = await APIKeyManager.validateDeepSeekKey(keyToTest)
            await MainActor.run {
                isTestingDeepSeek = false
                deepSeekTestResult = result
            }
        }
    }

    private func saveKeys() {
        saveErrorMessage = nil
        APIKeyManager.region = selectedRegion

        do {
            if !deepSeekKey.isEmpty {
                try APIKeyManager.setUserDeepSeekKey(deepSeekKey)
                deepSeekKey = ""
            }
            if !qwenKey.isEmpty {
                try APIKeyManager.setUserQwenKey(qwenKey)
                qwenKey = ""
            }
            refreshTrigger.toggle()
            onComplete?()
        } catch {
            saveErrorMessage = error.localizedDescription
        }
    }

    private func clearKeys() {
        APIKeyManager.clearUserKeys()
        deepSeekKey = ""
        qwenKey = ""
        deepSeekTestResult = nil
        refreshTrigger.toggle()
    }
}

#Preview {
    NavigationStack {
        AISettingsView()
    }
}
