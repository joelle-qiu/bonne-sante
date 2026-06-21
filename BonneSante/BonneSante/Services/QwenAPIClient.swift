import Foundation

/// Qwen API 连接验证
/// @author jiali.qiu
enum QwenAPIClient {

    /// 用最小文本请求验证 Key 是否有效（endpoint 需与地区设置一致）
    static func validateKey(_ apiKey: String, endpoint: URL) async -> APIValidationResult {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 15

        let body: [String: Any] = [
            "model": "qwen-vl-plus",
            "messages": [["role": "user", "content": "ping"]],
            "max_tokens": 5
        ]

        guard let httpBody = try? JSONSerialization.data(withJSONObject: body) else {
            return .networkError("请求构建失败")
        }
        request.httpBody = httpBody

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return .networkError("无效响应")
            }
            switch http.statusCode {
            case 200...299:
                return .success
            case 401, 403:
                return .invalidKey
            default:
                let body = String(data: data, encoding: .utf8) ?? ""
                return .networkError("HTTP \(http.statusCode): \(body.prefix(120))")
            }
        } catch {
            return .networkError(error.localizedDescription)
        }
    }
}
