import Foundation

/// Automatically compacts long conversations to keep the LLM context window healthy.
/// When the conversation exceeds `maxMessages`, older messages are replaced with a
/// concise text summary injected into the ChatSession instructions.
/// The full message history is always preserved in SwiftData — only the in-memory
/// ChatSession context is compacted.
@MainActor
final class ContextCompactor {

    private let llmService: LLMService
    private let memoryService: MemoryService

    /// Number of messages in the conversation that triggers compaction.
    let maxMessages = 20
    /// How many recent messages to keep intact after compaction.
    let keepRecentMessages = 6

    init(llmService: LLMService, memoryService: MemoryService) {
        self.llmService = llmService
        self.memoryService = memoryService
    }

    // MARK: - Compact if needed

    func compactIfNeeded(conversation: Conversation) {
        let messages = conversation.sortedMessages
            .filter { $0.isUser || $0.isAssistant }
        guard messages.count > maxMessages else { return }

        let oldMessages = Array(messages.dropLast(keepRecentMessages))
        let summary = Self.buildSummary(from: oldMessages)

        let facts = memoryService.factsForPrompt()
        llmService.resetWithCompactedContext(conversationSummary: summary, facts: facts)
    }

    // MARK: - Summary builder (static so ChatView can call it without a full compactor)

    static func buildSummary(from messages: [Message]) -> String {
        var result = ""
        var i = 0
        var pairs: [(q: String, a: String)] = []

        while i < messages.count {
            let msg = messages[i]
            if msg.isUser {
                let q = String(msg.content.prefix(100))
                var a = ""
                if i + 1 < messages.count, messages[i + 1].isAssistant {
                    a = String(messages[i + 1].content.prefix(100))
                    i += 1
                }
                pairs.append((q: q, a: a))
            }
            i += 1
        }

        // Keep at most the last 5 pairs to stay under ~300 token budget
        for pair in pairs.suffix(5) {
            result += "- Utente: \(pair.q)\n"
            if !pair.a.isEmpty {
                result += "  Jarvis: \(pair.a)\n"
            }
        }

        return result
    }
}
