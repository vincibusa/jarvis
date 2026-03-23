import SwiftData
import Foundation

enum MessageRole: String, Codable {
    case user
    case assistant
    case tool
    case system
}

@Model
final class Message {
    var id: UUID
    var role: String
    var content: String
    var toolName: String?
    var toolArgs: String?
    var timestamp: Date
    var conversation: Conversation?

    init(
        role: MessageRole,
        content: String,
        toolName: String? = nil,
        toolArgs: String? = nil
    ) {
        self.id = UUID()
        self.role = role.rawValue
        self.content = content
        self.toolName = toolName
        self.toolArgs = toolArgs
        self.timestamp = Date()
    }

    var roleEnum: MessageRole {
        MessageRole(rawValue: role) ?? .assistant
    }

    var isUser: Bool { role == MessageRole.user.rawValue }
    var isAssistant: Bool { role == MessageRole.assistant.rawValue }
    var isTool: Bool { role == MessageRole.tool.rawValue }
}
