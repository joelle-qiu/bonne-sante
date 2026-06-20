import Foundation
import Security

/// API Key 安全存储（Keychain）
/// @author jiali.qiu
enum KeychainService {
    private static let serviceName = "com.bonnesante.app.apikeys"

    enum Account: String {
        case deepSeek = "deepseek_api_key"
        case qwen = "qwen_api_key"
    }

    static func save(_ value: String, account: Account) throws {
        let data = Data(value.utf8)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account.rawValue
        ]

        SecItemDelete(query as CFDictionary)

        var attributes = query
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly

        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.saveFailed(status)
        }
    }

    static func load(account: Account) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account.rawValue,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(account: Account) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account.rawValue
        ]
        SecItemDelete(query as CFDictionary)
    }

    static func deleteAll() {
        delete(account: .deepSeek)
        delete(account: .qwen)
    }
}

enum KeychainError: LocalizedError {
    case saveFailed(OSStatus)

    var errorDescription: String? {
        switch self {
        case .saveFailed(let status):
            return "Keychain 保存失败 (\(status))"
        }
    }
}

enum APIValidationResult {
    case success
    case invalidKey
    case networkError(String)

    var message: String {
        switch self {
        case .success: return "连接成功"
        case .invalidKey: return "API Key 无效"
        case .networkError(let detail): return "网络错误：\(detail)"
        }
    }

    var isSuccess: Bool {
        if case .success = self { return true }
        return false
    }
}
