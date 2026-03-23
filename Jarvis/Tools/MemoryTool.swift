import Foundation

@MainActor
final class MemoryTool {

    private let memoryService: MemoryService
    private let embeddingService: EmbeddingService
    private let vectorStore: VectorStore

    /// Called after a fact is stored — lets LLMService refresh its system prompt.
    var onFactsChanged: (() -> Void)?

    init(memoryService: MemoryService, embeddingService: EmbeddingService, vectorStore: VectorStore) {
        self.memoryService = memoryService
        self.embeddingService = embeddingService
        self.vectorStore = vectorStore
    }

    // MARK: - Remember

    func remember(key: String, content: String) async -> String {
        // 1. Persist to SwiftData (source of truth / fallback)
        memoryService.remember(key: key, content: content)

        // 2. Embed and store in VectorStore for semantic recall
        // embed() auto-loads the model if not already loaded
        let text = "passage: \(key): \(content)"
        if let embedding = try? await embeddingService.embed(text: text) {
            let factId = key.lowercased().replacingOccurrences(of: " ", with: "_")
            vectorStore.insertMemory(id: factId, key: key, content: content, embedding: embedding)
        }
        // Unload embedding model after storing to free memory alongside the LLM
        embeddingService.unloadModel()

        // 3. Notify so LLMService can refresh the system prompt with updated top facts
        onFactsChanged?()

        return "Ho memorizzato: \(key) → \(content)"
    }

    // MARK: - Recall

    func recall(query: String) async -> String {
        // 1. Semantic search (embed() auto-loads the model if needed)
        let queryText = "query: \(query)"
        if let queryEmb = try? await embeddingService.embed(text: queryText) {
            let results = vectorStore.searchMemory(queryEmbedding: queryEmb, topK: 5)
            embeddingService.unloadModel()
            // Only return results with sufficient semantic relevance (≥ 70%)
            let relevant = results.filter { $0.score >= 0.70 }
            if !relevant.isEmpty {
                let lines = relevant.map { r in
                    "• \(r.key): \(r.content) (\(Int(r.score * 100))%)"
                }
                return "Ricordi trovati:\n" + lines.joined(separator: "\n")
            }
        } else {
            embeddingService.unloadModel()
        }

        // 2. Fallback: keyword search
        let facts = memoryService.recall(query: query)
        guard !facts.isEmpty else {
            return "Non ho trovato nulla in memoria riguardo a '\(query)'."
        }
        let lines = facts.map { "• \($0.key): \($0.content)" }
        return "Ricordi trovati:\n" + lines.joined(separator: "\n")
    }
}
