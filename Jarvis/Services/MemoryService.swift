import Foundation
import SwiftData
import Observation

@Observable
final class MemoryService {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // MARK: - Memory facts

    func remember(key: String, content: String) {
        let normalizedKey = key.lowercased().replacingOccurrences(of: " ", with: "_")
        let descriptor = FetchDescriptor<MemoryFact>(
            predicate: #Predicate { $0.key == normalizedKey }
        )
        if let existing = try? modelContext.fetch(descriptor).first {
            existing.content = content
        } else {
            modelContext.insert(MemoryFact(key: normalizedKey, content: content))
        }
        try? modelContext.save()
    }

    func recall(query: String) -> [MemoryFact] {
        let words = query.lowercased()
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
        let all = (try? modelContext.fetch(FetchDescriptor<MemoryFact>())) ?? []
        return all.filter { fact in
            let text = "\(fact.key) \(fact.content)".lowercased()
            return words.contains { text.contains($0) }
        }
    }

    func allFacts() -> [MemoryFact] {
        (try? modelContext.fetch(FetchDescriptor<MemoryFact>())) ?? []
    }

    func deleteFact(_ fact: MemoryFact) {
        modelContext.delete(fact)
        try? modelContext.save()
    }

    func clearAllMemory() {
        allFacts().forEach { modelContext.delete($0) }
        try? modelContext.save()
    }

    // MARK: - Conversations

    func createConversation(title: String = "Nuova conversazione") -> Conversation {
        let conv = Conversation(title: title)
        modelContext.insert(conv)
        try? modelContext.save()
        return conv
    }

    func fetchConversations() -> [Conversation] {
        let descriptor = FetchDescriptor<Conversation>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    func deleteConversation(_ conv: Conversation) {
        modelContext.delete(conv)
        try? modelContext.save()
    }

    func addMessage(
        to conversation: Conversation,
        role: MessageRole,
        content: String,
        toolName: String? = nil,
        toolArgs: String? = nil
    ) -> Message {
        let msg = Message(role: role, content: content, toolName: toolName, toolArgs: toolArgs)
        msg.conversation = conversation
        conversation.messages.append(msg)
        conversation.updatedAt = Date()
        modelContext.insert(msg)
        try? modelContext.save()
        return msg
    }

    // MARK: - Context for system prompt

    func factsForPrompt() -> [(key: String, content: String)] {
        allFacts().map { (key: $0.key, content: $0.content) }
    }
}
