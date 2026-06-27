import Foundation
import SwiftData

/// 聊天频道：营养顾问 / AI 健身教练
enum ChatMessageChannel {
    static let nutrition = "nutrition"
    static let workoutCoach = "workout_coach"
    /// 保留最近 N 轮对话（每轮 = 用户 + 助手）
    static let maxContextExchanges = 5
    static var maxContextMessages: Int { maxContextExchanges * 2 }
}

@Model
final class ChatMessage {
    var id: UUID
    var role: String  // "user" or "assistant"
    var content: String
    var createdAt: Date
    /// nutrition | workout_coach
    var channel: String
    /// 教练线程：WorkoutPlanEntry.id.uuidString；营养顾问为空
    var threadKey: String

    init(
        role: String,
        content: String,
        channel: String = ChatMessageChannel.nutrition,
        threadKey: String = ""
    ) {
        self.id = UUID()
        self.role = role
        self.content = content
        self.createdAt = Date()
        self.channel = channel
        self.threadKey = threadKey
    }
}
