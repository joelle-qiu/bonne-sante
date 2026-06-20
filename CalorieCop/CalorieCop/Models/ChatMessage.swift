import Foundation
import SwiftData

@Model
final class ChatMessage {
    var id: UUID
    var role: String  // "user" or "assistant"
    var content: String
    var createdAt: Date

    init(role: String, content: String) {
        self.id = UUID()
        self.role = role
        self.content = content
        self.createdAt = Date()
    }
}
