import Foundation

/// DeepSeek API 连接验证
/// @author jiali.qiu
enum DeepSeekAPIClient {

    static func validateKey(_ apiKey: String) async -> APIValidationResult {
        var request = URLRequest(url: APIKeyManager.deepSeekEndpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 15

        let body: [String: Any] = [
            "model": APIKeyManager.deepSeekModel,
            "messages": [["role": "user", "content": "ping"]],
            "max_tokens": 5
        ]

        guard let httpBody = try? JSONSerialization.data(withJSONObject: body) else {
            return .networkError("请求构建失败")
        }
        request.httpBody = httpBody

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return .networkError("无效响应")
            }
            switch http.statusCode {
            case 200...299: return .success
            case 401, 403: return .invalidKey
            default: return .networkError("HTTP \(http.statusCode)")
            }
        } catch {
            return .networkError(error.localizedDescription)
        }
    }
}
