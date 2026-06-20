import Foundation
import UIKit

/// 文字 AI 服务：DeepSeek（OpenAI 兼容格式）
/// 图像 AI 服务：Qwen VL（保留 CalorieCop 原实现，不做修改）
/// @author jiali.qiu
final class DeepSeekService: AIServiceProtocol {
    private var endpoint: URL { APIKeyManager.deepSeekEndpoint }
    private var qwenEndpoint: URL { APIKeyManager.qwenEndpoint }
    private let model = APIKeyManager.deepSeekModel
    private let logger = DebugLogger.shared

    func parseFoodInput(_ input: String) async throws -> NutritionInfo {
        try await parseFoodInput(input, preferences: [])
    }

    func parseFoodInput(_ input: String, preferences: [FoodPreference]) async throws -> NutritionInfo {
        let items = try await parseFoodInputMultiple(input, preferences: preferences)
        guard let first = items.first else {
            throw AIServiceError.parsingError("未能解析食物")
        }
        return first
    }

    func parseFoodInputMultiple(_ input: String, preferences: [FoodPreference]) async throws -> [NutritionInfo] {
        guard let apiKey = APIKeyManager.deepSeekAPIKey, !apiKey.isEmpty else {
            throw AIServiceError.apiKeyNotConfigured
        }

        let systemPrompt = FoodParsingPrompt.systemPrompt(with: preferences)
        let requestBody = ChatCompletionRequest(
            model: model,
            messages: [
                ChatMessagePayload(role: "system", content: systemPrompt),
                ChatMessagePayload(role: "user", content: input)
            ]
        )

        return try await sendTextRequestMultiple(requestBody, apiKey: apiKey)
    }

    func parseFoodImage(_ image: UIImage, additionalContext: String? = nil, preferences: [FoodPreference] = []) async throws -> NutritionInfo {
        let items = try await parseFoodImageMultiple(image, additionalContext: additionalContext, preferences: preferences)
        guard let first = items.first else {
            throw AIServiceError.parsingError("未能识别图片中的食物")
        }
        return first
    }

    // MARK: - Qwen VL（保留不变）

    func parseFoodImageMultiple(_ image: UIImage, additionalContext: String? = nil, preferences: [FoodPreference] = []) async throws -> [NutritionInfo] {
        guard let apiKey = APIKeyManager.qwenAPIKey, !apiKey.isEmpty else {
            throw AIServiceError.apiKeyNotConfigured
        }

        let resizedImage = resizeImage(image, maxDimension: 512)

        guard let imageData = resizedImage.jpegData(compressionQuality: 0.6) else {
            throw AIServiceError.parsingError("Failed to process image")
        }
        let base64String = imageData.base64EncodedString()

        var userPrompt = "请识别这张图片中的所有食物，并估算每种食物的营养成分。"
        if let context = additionalContext {
            userPrompt += " 额外信息：\(context)"
        }

        let systemPrompt = FoodParsingPrompt.systemPrompt(with: preferences)

        let requestBody: [String: Any] = [
            "model": "qwen-vl-plus",
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": [
                    ["type": "image_url", "image_url": ["url": "data:image/jpeg;base64,\(base64String)"]],
                    ["type": "text", "text": userPrompt]
                ]]
            ]
        ]

        var request = URLRequest(url: qwenEndpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIServiceError.invalidResponse
        }

        let rawString = String(data: data, encoding: .utf8) ?? "无法解码响应"
        logger.logAPIResponse(statusCode: httpResponse.statusCode, body: rawString)

        guard (200...299).contains(httpResponse.statusCode) else {
            throw AIServiceError.parsingError("Qwen API Error (\(httpResponse.statusCode)): \(rawString)")
        }

        struct QwenResponse: Decodable {
            let choices: [Choice]?
            let error: QwenError?

            struct Choice: Decodable {
                let message: Message
                struct Message: Decodable {
                    let content: String
                }
            }

            struct QwenError: Decodable {
                let message: String?
                let code: String?
            }
        }

        let qwenResponse: QwenResponse
        do {
            qwenResponse = try JSONDecoder().decode(QwenResponse.self, from: data)
        } catch {
            logger.logError(error, context: "Qwen response decode")
            throw AIServiceError.parsingError("Qwen响应格式错误: \(rawString.prefix(300))")
        }

        if let error = qwenResponse.error {
            throw AIServiceError.parsingError("Qwen错误: \(error.message ?? error.code ?? "未知错误")")
        }

        guard let content = qwenResponse.choices?.first?.message.content else {
            throw AIServiceError.parsingError("Qwen返回为空: \(rawString.prefix(300))")
        }

        return try parseNutritionJSON(from: content)
    }

    // MARK: - DeepSeek Text

    private func sendTextRequestMultiple(_ requestBody: ChatCompletionRequest, apiKey: String) async throws -> [NutritionInfo] {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(requestBody)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIServiceError.invalidResponse
        }

        let rawString = String(data: data, encoding: .utf8) ?? "无法解码响应"
        logger.logAPIResponse(statusCode: httpResponse.statusCode, body: rawString)

        guard (200...299).contains(httpResponse.statusCode) else {
            throw AIServiceError.parsingError("DeepSeek API Error (\(httpResponse.statusCode)): \(rawString)")
        }

        let chatResponse: ChatCompletionResponse
        do {
            chatResponse = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)
        } catch {
            logger.logError(error, context: "DeepSeek response decode")
            throw AIServiceError.parsingError("API响应格式错误: \(rawString.prefix(300))")
        }

        if let apiError = chatResponse.error {
            throw AIServiceError.parsingError("API错误: \(apiError.message ?? apiError.code ?? "未知错误")")
        }

        guard let content = chatResponse.choices?.first?.message.content else {
            throw AIServiceError.parsingError("API返回为空: \(rawString.prefix(300))")
        }

        return try parseNutritionJSON(from: content)
    }

    private func parseNutritionJSON(from content: String) throws -> [NutritionInfo] {
        let jsonString = extractJSON(from: content)
        logger.log("Extracted JSON: \(jsonString)")

        guard let contentData = jsonString.data(using: .utf8) else {
            throw AIServiceError.parsingError("无法转换内容")
        }

        do {
            return try JSONDecoder().decode([NutritionInfo].self, from: contentData)
        } catch {
            do {
                let single = try JSONDecoder().decode(NutritionInfo.self, from: contentData)
                return [single]
            } catch {
                logger.logError(error, context: "NutritionInfo decode. JSON: \(jsonString)")
                throw AIServiceError.parsingError("营养信息解析失败: \(jsonString.prefix(200))")
            }
        }
    }

    private func extractJSON(from content: String) -> String {
        let cleaned = content
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if let start = cleaned.firstIndex(of: "["),
           let end = cleaned.lastIndex(of: "]") {
            return String(cleaned[start...end])
        }

        if let start = cleaned.firstIndex(of: "{"),
           let end = cleaned.lastIndex(of: "}") {
            return String(cleaned[start...end])
        }

        if cleaned.contains(":") && !cleaned.contains("{") && !cleaned.contains("[") {
            return convertYAMLToJSON(cleaned)
        }

        return cleaned
    }

    private func convertYAMLToJSON(_ yaml: String) -> String {
        var dict: [String: Any] = [:]
        let lines = yaml.components(separatedBy: .newlines)

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }

            if let colonIndex = trimmed.firstIndex(of: ":") {
                let key = String(trimmed[..<colonIndex]).trimmingCharacters(in: .whitespaces)
                let value = String(trimmed[trimmed.index(after: colonIndex)...]).trimmingCharacters(in: .whitespaces)
                guard !value.isEmpty else { continue }

                if let doubleValue = Double(value) {
                    dict[key] = doubleValue
                } else if let intValue = Int(value) {
                    dict[key] = intValue
                } else {
                    var strValue = value
                    if (strValue.hasPrefix("\"") && strValue.hasSuffix("\"")) ||
                       (strValue.hasPrefix("'") && strValue.hasSuffix("'")) {
                        strValue = String(strValue.dropFirst().dropLast())
                    }
                    dict[key] = strValue
                }
            }
        }

        if let jsonData = try? JSONSerialization.data(withJSONObject: dict),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            return jsonString
        }

        return yaml
    }

    private func resizeImage(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let size = image.size
        let maxSize = max(size.width, size.height)

        if maxSize <= maxDimension {
            return image
        }

        let scale = maxDimension / maxSize
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)

        UIGraphicsBeginImageContextWithOptions(newSize, false, 1.0)
        image.draw(in: CGRect(origin: .zero, size: newSize))
        let resizedImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()

        return resizedImage ?? image
    }
}

// MARK: - OpenAI-compatible request/response

private struct ChatCompletionRequest: Encodable {
    let model: String
    let messages: [ChatMessagePayload]
}

private struct ChatMessagePayload: Encodable {
    let role: String
    let content: String
}

private struct ChatCompletionResponse: Decodable {
    let choices: [Choice]?
    let error: APIErrorPayload?

    struct Choice: Decodable {
        let message: ResponseMessage
    }

    struct ResponseMessage: Decodable {
        let content: String
    }

    struct APIErrorPayload: Decodable {
        let message: String?
        let code: String?
    }
}
