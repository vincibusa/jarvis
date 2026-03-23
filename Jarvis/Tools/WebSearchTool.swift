import Foundation

@MainActor
final class WebSearchTool {

    private let searchService = WebSearchService()

    func webSearch(query: String) async -> String {
        do {
            let results = try await searchService.search(query: query, maxResults: 5)
            if results.isEmpty {
                return "Nessun risultato trovato per: \(query)"
            }

            var output = "Risultati per \"\(query)\":\n\n"
            for (i, result) in results.enumerated() {
                output += "\(i + 1). \(result.title)\n"
                output += "   \(result.snippet)\n"
                output += "   URL: \(result.url)\n\n"
            }

            // Fetch content from the top result for extra context (lightweight)
            if let topURL = URL(string: results[0].url) {
                if let content = try? await searchService.fetchPageContent(url: topURL, maxChars: 1500),
                   !content.isEmpty {
                    output += "Contenuto pagina principale:\n\(content)\n"
                }
            }

            return output
        } catch {
            return "Errore nella ricerca web: \(error.localizedDescription)"
        }
    }
}
