import Foundation

struct SearchResult: Sendable {
    let title: String
    let url: String
    let snippet: String
}

actor WebSearchService {

    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10
        config.timeoutIntervalForResource = 10
        return URLSession(configuration: config)
    }()

    // MARK: - Search

    /// Search DuckDuckGo HTML version (no API key needed)
    func search(query: String, maxResults: Int = 5) async throws -> [SearchResult] {
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://html.duckduckgo.com/html/?q=\(encoded)") else {
            throw WebSearchError.invalidQuery
        }

        var request = URLRequest(url: url)
        request.setValue("Jarvis/1.0", forHTTPHeaderField: "User-Agent")
        request.setValue("it-IT,it;q=0.9,en;q=0.8", forHTTPHeaderField: "Accept-Language")

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw WebSearchError.badResponse
        }

        guard let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
            throw WebSearchError.decodingFailed
        }

        return parseResults(from: html, maxResults: maxResults)
    }

    // MARK: - Fetch page content

    /// Fetch and extract text content from a web page
    func fetchPageContent(url: URL, maxChars: Int = 3000) async throws -> String {
        var request = URLRequest(url: url)
        request.setValue("Jarvis/1.0", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw WebSearchError.badResponse
        }

        guard let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
            throw WebSearchError.decodingFailed
        }

        let text = stripHTML(html)
        return text.isEmpty ? "Impossibile estrarre contenuto dalla pagina." : String(text.prefix(maxChars))
    }

    // MARK: - HTML parsing helpers

    private func parseResults(from html: String, maxResults: Int) -> [SearchResult] {
        var results: [SearchResult] = []

        // DuckDuckGo HTML wraps each result in a <div class="result ..."> block.
        // Titles/links: <a class="result__a" href="...">title</a>
        // Snippets:     <a class="result__snippet" ...>snippet</a>
        //               or <div class="result__snippet">snippet</div>

        // Split on result blocks
        let blocks = splitBlocks(html, separator: "result__title")

        for block in blocks {
            guard results.count < maxResults else { break }

            let title = extractTagContent(from: block, tagClass: "result__a")
            let rawURL = extractAttribute(from: block, tagClass: "result__a", attribute: "href")
            let snippet = extractTagContent(from: block, tagClass: "result__snippet")

            guard !title.isEmpty, !rawURL.isEmpty else { continue }

            // DuckDuckGo sometimes wraps URLs in a redirect; grab uddg= param or use as-is
            let finalURL = resolveURL(rawURL)
            let cleanTitle = decodeHTMLEntities(stripTags(title))
            let cleanSnippet = decodeHTMLEntities(stripTags(snippet))

            results.append(SearchResult(title: cleanTitle, url: finalURL, snippet: cleanSnippet))
        }

        return results
    }

    private func splitBlocks(_ html: String, separator: String) -> [String] {
        var parts: [String] = []
        var remaining = html
        while let range = remaining.range(of: separator) {
            let before = String(remaining[remaining.startIndex..<range.lowerBound])
            if !before.isEmpty { parts.append(before) }
            remaining = String(remaining[range.upperBound...])
        }
        if !remaining.isEmpty { parts.append(remaining) }
        // Drop the first part (it's the header before the first result)
        return parts.count > 1 ? Array(parts.dropFirst()) : parts
    }

    private func extractTagContent(from html: String, tagClass: String) -> String {
        // Find class="tagClass" or class="tagClass ..." then grab content until </a> or </div>
        guard let classRange = html.range(of: "class=\"\(tagClass)") else { return "" }
        let afterClass = String(html[classRange.upperBound...])
        // Skip to end of opening tag >
        guard let tagEnd = afterClass.range(of: ">") else { return "" }
        let content = String(afterClass[tagEnd.upperBound...])
        // Take until first closing tag
        if let closeA = content.range(of: "</a>") {
            return String(content[content.startIndex..<closeA.lowerBound])
        }
        if let closeDiv = content.range(of: "</div>") {
            return String(content[content.startIndex..<closeDiv.lowerBound])
        }
        return String(content.prefix(200))
    }

    private func extractAttribute(from html: String, tagClass: String, attribute: String) -> String {
        guard let classRange = html.range(of: "class=\"\(tagClass)") else { return "" }
        // Search backwards for the opening <a tag before this class
        let before = String(html[html.startIndex..<classRange.lowerBound])
        guard let tagStart = before.range(of: "<a ", options: .backwards) else { return "" }
        let tagContent = String(html[tagStart.lowerBound...])
        guard let tagEnd = tagContent.range(of: ">") else { return "" }
        let tag = String(tagContent[tagContent.startIndex..<tagEnd.upperBound])

        // Extract attribute value
        let attrKey = "\(attribute)=\""
        guard let attrRange = tag.range(of: attrKey) else { return "" }
        let afterAttr = String(tag[attrRange.upperBound...])
        guard let closeQuote = afterAttr.range(of: "\"") else { return "" }
        return String(afterAttr[afterAttr.startIndex..<closeQuote.lowerBound])
    }

    private func resolveURL(_ raw: String) -> String {
        // DuckDuckGo uses /l/?uddg=<encoded_url>&... redirect links
        if raw.hasPrefix("/l/?") || raw.hasPrefix("//duckduckgo.com/l/?") {
            let full = raw.hasPrefix("//") ? "https:" + raw : "https://duckduckgo.com" + raw
            if let components = URLComponents(string: full),
               let uddg = components.queryItems?.first(where: { $0.name == "uddg" })?.value,
               let decoded = uddg.removingPercentEncoding {
                return decoded
            }
        }
        if raw.hasPrefix("http") { return raw }
        return "https://" + raw
    }

    // MARK: - HTML stripping

    private func stripHTML(_ html: String) -> String {
        var text = html

        // Remove <script>...</script> blocks
        text = removeBlocks(from: text, openTag: "<script", closeTag: "</script>")
        // Remove <style>...</style> blocks
        text = removeBlocks(from: text, openTag: "<style", closeTag: "</style>")
        // Remove <noscript>...</noscript>
        text = removeBlocks(from: text, openTag: "<noscript", closeTag: "</noscript>")

        // Strip all remaining tags
        text = stripTags(text)

        // Decode HTML entities
        text = decodeHTMLEntities(text)

        // Collapse whitespace
        text = text.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        return text
    }

    private func removeBlocks(from html: String, openTag: String, closeTag: String) -> String {
        var result = html
        while let start = result.range(of: openTag, options: .caseInsensitive),
              let end = result.range(of: closeTag, options: .caseInsensitive, range: start.lowerBound..<result.endIndex) {
            let removeEnd = min(end.upperBound, result.endIndex)
            result.removeSubrange(start.lowerBound..<removeEnd)
        }
        return result
    }

    private func stripTags(_ html: String) -> String {
        var result = ""
        var inTag = false
        for char in html {
            if char == "<" { inTag = true; continue }
            if char == ">" { inTag = false; continue }
            if !inTag { result.append(char) }
        }
        return result
    }

    private func decodeHTMLEntities(_ text: String) -> String {
        var result = text
        let entities: [(String, String)] = [
            ("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"),
            ("&quot;", "\""), ("&#39;", "'"), ("&apos;", "'"),
            ("&nbsp;", " "), ("&hellip;", "…"), ("&mdash;", "—"),
            ("&ndash;", "–"), ("&laquo;", "«"), ("&raquo;", "»"),
        ]
        for (entity, char) in entities {
            result = result.replacingOccurrences(of: entity, with: char)
        }
        // Remove remaining numeric entities like &#123;
        // Simple pass: strip anything matching &#...;
        var cleaned = ""
        var i = result.startIndex
        while i < result.endIndex {
            if result[i] == "&" {
                if let semiRange = result.range(of: ";", range: i..<result.endIndex) {
                    let entity = String(result[i...semiRange.lowerBound])
                    if entity.count <= 8 {
                        i = semiRange.upperBound
                        continue
                    }
                }
            }
            cleaned.append(result[i])
            i = result.index(after: i)
        }
        return cleaned
    }

    // MARK: - Errors

    enum WebSearchError: LocalizedError {
        case invalidQuery
        case badResponse
        case decodingFailed

        var errorDescription: String? {
            switch self {
            case .invalidQuery:    return "Query di ricerca non valida."
            case .badResponse:     return "Risposta non valida dal server di ricerca."
            case .decodingFailed:  return "Impossibile decodificare la risposta HTML."
            }
        }
    }
}
