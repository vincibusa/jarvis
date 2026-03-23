import Foundation
import SwiftData
import UniformTypeIdentifiers

@MainActor
final class DocumentService {

    // MARK: - Dependencies

    private let embeddingService: EmbeddingService
    private let vectorStore: VectorStore
    private let modelContext: ModelContext

    // MARK: - Init

    init(embeddingService: EmbeddingService, modelContext: ModelContext) {
        self.embeddingService = embeddingService
        self.modelContext = modelContext

        // Vector store lives in the app's Documents directory
        let dbURL = Self.vectorStoreURL()
        self.vectorStore = VectorStore(path: dbURL)
    }

    // MARK: - Public API

    /// Import a document: parse, chunk, embed, and persist to VectorStore + SwiftData.
    func importDocument(url: URL) async throws -> Document {
        // Ensure embedding model is loaded
        if case .idle = embeddingService.state {
            await embeddingService.loadModel()
        }
        guard case .ready = embeddingService.state else {
            throw DocumentError.embeddingNotReady
        }

        // Determine file type and parser
        let ext = url.pathExtension.lowercased()
        let parser: DocumentParser = try parserFor(extension: ext)

        // Parse text content
        let text = try await parser.parse(url: url)

        // Chunk the text
        let chunks = ChunkingService.chunk(text: text)
        guard !chunks.isEmpty else {
            throw DocumentError.emptyDocument
        }

        // Compute file size
        let fileSize = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0

        // Create SwiftData record
        let document = Document(
            name: url.deletingPathExtension().lastPathComponent,
            fileType: ext,
            chunkCount: chunks.count,
            fileSize: fileSize
        )
        modelContext.insert(document)

        // Embed and store each chunk
        let docIdStr = document.id.uuidString
        for (index, chunk) in chunks.enumerated() {
            // Prefix following E5 multilingual convention: "passage: <text>"
            let prefixed = "passage: \(chunk)"
            let embedding = try await embeddingService.embed(text: prefixed)

            vectorStore.insert(
                id: "\(docIdStr)_\(index)",
                documentId: docIdStr,
                content: chunk,
                embedding: embedding,
                chunkIndex: index
            )
        }

        // Unload embedding model to free ~300 MB alongside the LLM
        embeddingService.unloadModel()

        try modelContext.save()
        return document
    }

    /// Delete a document and all its chunks.
    func deleteDocument(id: UUID) async {
        let idStr = id.uuidString
        vectorStore.deleteByDocument(id: idStr)

        let descriptor = FetchDescriptor<Document>(
            predicate: #Predicate { $0.id == id }
        )
        if let docs = try? modelContext.fetch(descriptor),
           let doc = docs.first {
            modelContext.delete(doc)
            try? modelContext.save()
        }
    }

    /// Search documents with a query and return ranked results.
    func searchDocuments(
        query: String,
        topK: Int = 3
    ) async throws -> [(content: String, documentName: String, score: Float)] {
        if case .idle = embeddingService.state {
            await embeddingService.loadModel()
        }
        guard case .ready = embeddingService.state else {
            throw DocumentError.embeddingNotReady
        }

        // Prefix following E5 convention: "query: <text>"
        let prefixedQuery = "query: \(query)"
        let queryEmbedding = try await embeddingService.embed(text: prefixedQuery)

        let results = vectorStore.search(queryEmbedding: queryEmbedding, topK: topK)
        // Unload embedding model after search to free memory alongside the LLM
        embeddingService.unloadModel()

        // Resolve document names from SwiftData
        return results.compactMap { chunk in
            guard let uuid = UUID(uuidString: chunk.documentId) else { return nil }
            let descriptor = FetchDescriptor<Document>(
                predicate: #Predicate { $0.id == uuid }
            )
            let docName = (try? modelContext.fetch(descriptor).first?.name) ?? chunk.documentId
            return (content: chunk.content, documentName: docName, score: chunk.score)
        }
    }

    /// List all imported documents.
    func listDocuments() -> [Document] {
        let descriptor = FetchDescriptor<Document>(
            sortBy: [SortDescriptor(\.importedAt, order: .reverse)]
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    // MARK: - Helpers

    private func parserFor(extension ext: String) throws -> DocumentParser {
        switch ext {
        case "pdf":
            return PDFDocumentParser()
        case "txt", "md", "csv", "text":
            return PlainTextParser()
        case "docx":
            return DocxParser()
        default:
            throw DocumentError.unsupportedFormat(ext)
        }
    }

    private static func vectorStoreURL() -> URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent("jarvis_vectors.sqlite3")
    }

    // MARK: - Errors

    enum DocumentError: LocalizedError {
        case embeddingNotReady
        case emptyDocument
        case unsupportedFormat(String)

        var errorDescription: String? {
            switch self {
            case .embeddingNotReady:
                return "Il modello di embedding non è pronto."
            case .emptyDocument:
                return "Il documento non contiene testo estraibile."
            case .unsupportedFormat(let ext):
                return "Formato file non supportato: .\(ext)"
            }
        }
    }
}
