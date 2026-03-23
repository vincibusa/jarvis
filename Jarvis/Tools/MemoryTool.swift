import Foundation

@MainActor
final class MemoryTool {

    private let memoryService: MemoryService

    init(memoryService: MemoryService) {
        self.memoryService = memoryService
    }

    // MARK: - Remember

    func remember(key: String, content: String) -> String {
        memoryService.remember(key: key, content: content)
        return "Ho memorizzato: \(key) → \(content)"
    }

    // MARK: - Recall

    func recall(query: String) -> String {
        let facts = memoryService.recall(query: query)
        guard !facts.isEmpty else {
            return "Non ho trovato nulla in memoria riguardo a '\(query)'."
        }
        let lines = facts.map { "• \($0.key): \($0.content)" }
        return "Ricordi trovati per '\(query)':\n" + lines.joined(separator: "\n")
    }
}
