import Foundation

/// AI 服务能力状态
/// @author jiali.qiu
struct AIServiceStatus: Equatable {
    var isDeepSeekReady: Bool
    var isQwenReady: Bool
    var foodParsingAvailable: Bool
    var advisorAvailable: Bool
    var photoRecognitionAvailable: Bool

    static var current: AIServiceStatus {
        let deepSeek = APIKeyManager.isDeepSeekConfigured
        let qwen = APIKeyManager.isQwenConfigured
        return AIServiceStatus(
            isDeepSeekReady: deepSeek,
            isQwenReady: qwen,
            foodParsingAvailable: deepSeek,
            advisorAvailable: deepSeek,
            photoRecognitionAvailable: qwen
        )
    }

    var summaryLabel: String {
        if foodParsingAvailable && photoRecognitionAvailable { return "已就绪" }
        if foodParsingAvailable { return "部分可用" }
        return "未配置"
    }
}
