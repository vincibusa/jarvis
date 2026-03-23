import Foundation

@MainActor
final class DocumentTool {

    private let documentService: DocumentService

    init(documentService: DocumentService) {
        self.documentService = documentService
    }

    // MARK: - Search

    func searchDocuments(query: String, topK: Int = 3) async throws -> String {
        let results = try await documentService.searchDocuments(query: query, topK: topK)

        if results.isEmpty {
            return "Nessun documento pertinente trovato per la query: \"\(query)\"."
        }

        // Cap each chunk to 800 chars to prevent LLM context explosion.
        // CVs and long documents often produce 3000+ char chunks that make generation very slow.
        let maxChunkChars = 800

        var lines: [String] = ["Risultati ricerca nei documenti per \"\(query)\":"]
        for (i, result) in results.enumerated() {
            let percent = Int(result.score * 100)
            lines.append("\n[\(i + 1)] Da \"\(result.documentName)\" (rilevanza: \(percent)%):")
            if result.content.count > maxChunkChars {
                lines.append(String(result.content.prefix(maxChunkChars)) + "… [troncato]")
            } else {
                lines.append(result.content)
            }
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - List

    func listDocuments() -> String {
        let docs = documentService.listDocuments()

        if docs.isEmpty {
            return "Nessun documento importato. Importa documenti dalla sezione Documenti dell'app."
        }

        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "it_IT")
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .none

        var lines: [String] = ["Documenti importati (\(docs.count)):"]
        for doc in docs {
            let date = dateFormatter.string(from: doc.importedAt)
            let sizeKB = doc.fileSize > 0 ? " • \(doc.fileSize / 1024) KB" : ""
            lines.append("• \(doc.name).\(doc.fileType) — \(doc.chunkCount) sezioni — \(date)\(sizeKB)")
        }

        return lines.joined(separator: "\n")
    }
}
