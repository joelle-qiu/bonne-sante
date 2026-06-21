import Foundation

enum APIKeyManager {
    private static let deepSeekKeyUserDefaultsKey = "user_deepseek_api_key"
    private static let legacyMiniMaxKeyUserDefaultsKey = "user_minimax_api_key"
    private static let qwenKeyUserDefaultsKey = "user_qwen_api_key"
    private static let regionUserDefaultsKey = "user_api_region"
    private static let migrationCompletedKey = "api_key_migration_v1_completed"
    private static let keychainMigrationCompletedKey = "api_key_keychain_migration_v2_completed"
    private static let reportAIAssistKey = "report_ai_assist_enabled"

    static let deepSeekModel = "deepseek-chat"

    /// 体检报告 DeepSeek 文本结构化辅助（脱敏 OCR 文本，不上传原图）
    static var isReportAIAssistEnabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: reportAIAssistKey) == nil {
                return true
            }
            return UserDefaults.standard.bool(forKey: reportAIAssistKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: reportAIAssistKey)
        }
    }

    static var deepSeekEndpoint: URL {
        URL(string: "https://api.deepseek.com/v1/chat/completions")!
    }

    static var deepSeekAPIKey: String? {
        migrateKeysIfNeeded()
        if let key = KeychainService.load(account: .deepSeek), !key.isEmpty { return key }
        return developerDeepSeekKey
    }

    static var qwenAPIKey: String? {
        migrateKeysIfNeeded()
        if let key = KeychainService.load(account: .qwen), !key.isEmpty { return key }
        return developerQwenKey
    }

    static var isDeepSeekConfigured: Bool {
        guard let key = deepSeekAPIKey else { return false }
        return !key.isEmpty
    }

    static var isQwenConfigured: Bool {
        guard let key = qwenAPIKey else { return false }
        return !key.isEmpty
    }

    // MARK: - User Key Management

    static func setUserDeepSeekKey(_ key: String) throws {
        try KeychainService.save(key, account: .deepSeek)
        UserDefaults.standard.removeObject(forKey: deepSeekKeyUserDefaultsKey)
    }

    static func setUserQwenKey(_ key: String) throws {
        try KeychainService.save(key, account: .qwen)
        UserDefaults.standard.removeObject(forKey: qwenKeyUserDefaultsKey)
    }

    static func clearUserKeys() {
        KeychainService.deleteAll()
        UserDefaults.standard.removeObject(forKey: deepSeekKeyUserDefaultsKey)
        UserDefaults.standard.removeObject(forKey: qwenKeyUserDefaultsKey)
        UserDefaults.standard.removeObject(forKey: legacyMiniMaxKeyUserDefaultsKey)
    }

    static var hasUserDeepSeekKey: Bool {
        migrateKeysIfNeeded()
        guard let key = KeychainService.load(account: .deepSeek) else { return false }
        return !key.isEmpty
    }

    static var hasUserQwenKey: Bool {
        migrateKeysIfNeeded()
        guard let key = KeychainService.load(account: .qwen) else { return false }
        return !key.isEmpty
    }

    static func validateDeepSeekKey(_ key: String) async -> APIValidationResult {
        await DeepSeekAPIClient.validateKey(key)
    }

    static func validateQwenKey(_ key: String, region: APIRegion? = nil) async -> APIValidationResult {
        let endpoint = (region ?? APIKeyManager.region).qwenEndpoint
        return await QwenAPIClient.validateKey(key, endpoint: endpoint)
    }

    // MARK: - Region (Qwen only)

    static var region: APIRegion {
        get {
            guard let rawValue = UserDefaults.standard.string(forKey: regionUserDefaultsKey),
                  let region = APIRegion(rawValue: rawValue) else {
                return .china
            }
            return region
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: regionUserDefaultsKey)
        }
    }

    static var qwenEndpoint: URL {
        region.qwenEndpoint
    }

    // MARK: - Migration

    private static func migrateKeysIfNeeded() {
        migrateLegacyMiniMaxKeyIfNeeded()
        migrateUserDefaultsToKeychainIfNeeded()
    }

    private static func migrateLegacyMiniMaxKeyIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: migrationCompletedKey) else { return }

        if KeychainService.load(account: .deepSeek) == nil,
           let legacy = UserDefaults.standard.string(forKey: legacyMiniMaxKeyUserDefaultsKey),
           !legacy.isEmpty {
            try? KeychainService.save(legacy, account: .deepSeek)
        }

        if KeychainService.load(account: .deepSeek) == nil,
           let oldDeepSeek = UserDefaults.standard.string(forKey: deepSeekKeyUserDefaultsKey),
           !oldDeepSeek.isEmpty {
            try? KeychainService.save(oldDeepSeek, account: .deepSeek)
        }

        UserDefaults.standard.set(true, forKey: migrationCompletedKey)
    }

    private static func migrateUserDefaultsToKeychainIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: keychainMigrationCompletedKey) else { return }

        if KeychainService.load(account: .deepSeek) == nil,
           let key = UserDefaults.standard.string(forKey: deepSeekKeyUserDefaultsKey),
           !key.isEmpty {
            try? KeychainService.save(key, account: .deepSeek)
            UserDefaults.standard.removeObject(forKey: deepSeekKeyUserDefaultsKey)
        }

        if KeychainService.load(account: .qwen) == nil,
           let key = UserDefaults.standard.string(forKey: qwenKeyUserDefaultsKey),
           !key.isEmpty {
            try? KeychainService.save(key, account: .qwen)
            UserDefaults.standard.removeObject(forKey: qwenKeyUserDefaultsKey)
        }

        UserDefaults.standard.set(true, forKey: keychainMigrationCompletedKey)
    }

    private static var developerDeepSeekKey: String? {
        let key = Secrets.deepSeekAPIKey
        if !key.isEmpty && key != "your_api_key_here" { return key }
        return ProcessInfo.processInfo.environment["DEEPSEEK_API_KEY"]
    }

    private static var developerQwenKey: String? {
        let key = Secrets.qwenAPIKey
        if !key.isEmpty && key != "your_api_key_here" { return key }
        return ProcessInfo.processInfo.environment["QWEN_API_KEY"]
    }
}

enum APIRegion: String, CaseIterable {
    case china = "china"
    case international = "international"

    var displayName: String {
        switch self {
        case .china: return "中国大陆 (China)"
        case .international: return "国际 (International)"
        }
    }

    var qwenEndpoint: URL {
        switch self {
        case .china:
            return URL(string: "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions")!
        case .international:
            return URL(string: "https://dashscope-intl.aliyuncs.com/compatible-mode/v1/chat/completions")!
        }
    }
}
