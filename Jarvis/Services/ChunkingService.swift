import Foundation

enum ChunkingService {

    /// Split text into overlapping chunks of roughly `chunkSize` words with `overlap` word overlap.
    /// Splits on paragraph boundaries first; further splits large paragraphs on sentence boundaries.
    static func chunk(
        text: String,
        chunkSize: Int = 500,
        overlap: Int = 50
    ) -> [String] {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }

        // 1. Split into paragraphs
        let paragraphs = text.components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        // 2. Accumulate paragraphs into word-count-limited chunks
        var chunks: [String] = []
        var currentWords: [String] = []

        func flush() {
            if !currentWords.isEmpty {
                chunks.append(currentWords.joined(separator: " "))
            }
        }

        for paragraph in paragraphs {
            let paraWords = paragraph.split(separator: " ", omittingEmptySubsequences: true).map(String.init)

            // If a single paragraph is too large, split it by sentences
            if paraWords.count > chunkSize {
                let sentences = splitSentences(paragraph)
                for sentence in sentences {
                    let sWords = sentence.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
                    if currentWords.count + sWords.count > chunkSize {
                        flush()
                        // Keep overlap words from previous chunk
                        currentWords = Array(currentWords.suffix(overlap))
                    }
                    currentWords += sWords
                }
            } else {
                if currentWords.count + paraWords.count > chunkSize {
                    flush()
                    currentWords = Array(currentWords.suffix(overlap))
                }
                currentWords += paraWords
            }
        }

        // Flush remaining words
        if !currentWords.isEmpty {
            chunks.append(currentWords.joined(separator: " "))
        }

        return chunks
    }

    // MARK: - Sentence splitter

    private static func splitSentences(_ text: String) -> [String] {
        var sentences: [String] = []
        let terminators: Set<Character> = [".", "!", "?", ";"]
        var current = ""

        for char in text {
            current.append(char)
            if terminators.contains(char) {
                let trimmed = current.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty {
                    sentences.append(trimmed)
                }
                current = ""
            }
        }
        let trimmed = current.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty {
            sentences.append(trimmed)
        }
        return sentences
    }
}
