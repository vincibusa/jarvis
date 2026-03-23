import Foundation
import MLXLLM
import MLXLMCommon
import MLX
import Observation
import Tokenizers

@Observable
@MainActor
final class LLMService {

    // MARK: - State

    enum State: Equatable {
        case idle
        case downloading(progress: Double)
        case loading
        case ready
        case generating
        case error(String)

        var statusDot: DotStatus {
            switch self {
            case .ready:      return .green
            case .generating: return .orange
            default:          return .gray
            }
        }

        enum DotStatus { case green, orange, gray }
    }

    var state: State = .idle
    var streamingText: String = ""
    var tokensPerSecond: Double = 0

    private(set) var modelContainer: ModelContainer?
    private(set) var chatSession: ChatSession?

    var toolRouter: ToolRouter?

    static let modelID = "mlx-community/Qwen3.5-2B-OptiQ-4bit"

    // MARK: - Tool configuration

    func configureTools(router: ToolRouter) {
        self.toolRouter = router
        if let container = modelContainer {
            createSession(container: container)
        }
    }

    private func createSession(container: ModelContainer) {
        let tools: [ToolSpec]? = toolRouter != nil ? ToolDefinitions.allToolSpecs : nil
        let router = self.toolRouter

        let session = ChatSession(
            container,
            instructions: Self.buildSystemPrompt(),
            generateParameters: GenerateParameters(
                maxTokens: 1024,
                temperature: 0.7,
                topP: 0.9,
                repetitionPenalty: 1.1
            ),
            tools: tools,
            toolDispatch: router != nil ? { @Sendable toolCall in
                let name = toolCall.function.name
                let args = toolCall.function.arguments.mapValues { $0.anyValue }
                return try await router!.execute(name: name, arguments: args)
            } : nil
        )
        self.chatSession = session
    }

    // MARK: - Model lifecycle

    func loadModel() async {
        guard case .idle = state else { return }
        state = .downloading(progress: 0)

        do {
            let config = ModelConfiguration(id: Self.modelID)

            let container = try await LLMModelFactory.shared.loadContainer(
                configuration: config
            ) { [weak self] progress in
                Task { @MainActor [weak self] in
                    self?.state = .downloading(progress: progress.fractionCompleted)
                }
            }

            self.modelContainer = container
            state = .loading
            createSession(container: container)
            state = .ready

        } catch {
            state = .error(error.localizedDescription)
        }
    }

    func resetModel() {
        chatSession = nil
        modelContainer = nil
        state = .idle
    }

    // MARK: - Generation

    /// Sends a message and returns an AsyncThrowingStream of text chunks.
    /// Filters out <think>...</think> reasoning blocks automatically.
    /// When the model emits a tool call, executes it via ToolRouter and feeds result back.
    func send(prompt: String) -> AsyncThrowingStream<String, Error> {
        guard let session = chatSession else {
            return AsyncThrowingStream { continuation in
                continuation.finish(throwing: JarvisError.modelNotLoaded)
            }
        }

        state = .generating
        streamingText = ""

        return AsyncThrowingStream { [weak self] continuation in
            Task { [weak self] in
                guard let self else { continuation.finish(); return }
                var thinkBuffer = ""
                var inThinkBlock = false
                var tokenCount = 0
                let startTime = Date()

                do {
                    for try await generation in session.streamResponse(to: prompt) {
                        tokenCount += 1
                        let filtered = self.processChunk(
                            generation,
                            buffer: &thinkBuffer,
                            inBlock: &inThinkBlock
                        )
                        if !filtered.isEmpty {
                            await MainActor.run {
                                self.streamingText += filtered
                            }
                            continuation.yield(filtered)
                        }
                    }

                    let elapsed = Date().timeIntervalSince(startTime)
                    await MainActor.run {
                        self.tokensPerSecond = elapsed > 0
                            ? Double(tokenCount) / elapsed
                            : 0
                        self.state = .ready
                    }
                    continuation.finish()
                } catch {
                    await MainActor.run { self.state = .error(error.localizedDescription) }
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    func resetConversation() {
        guard let container = modelContainer else { return }
        createSession(container: container)
        streamingText = ""
    }

    func updateSystemPrompt(_ prompt: String) {
        chatSession?.instructions = prompt
    }

    // MARK: - Download check

    var isModelDownloaded: Bool {
        let hubDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let modelDir = hubDir
            .appendingPathComponent("huggingface")
            .appendingPathComponent("models")
            .appendingPathComponent("mlx-community")
            .appendingPathComponent("Qwen3.5-2B-OptiQ-4bit")
        return FileManager.default.fileExists(atPath: modelDir.path)
    }

    // MARK: - Think block filtering

    private func processChunk(
        _ text: String,
        buffer: inout String,
        inBlock: inout Bool
    ) -> String {
        var output = ""
        var remaining = buffer + text
        buffer = ""

        while !remaining.isEmpty {
            if inBlock {
                if let endRange = remaining.range(of: "</think>") {
                    remaining = String(remaining[endRange.upperBound...])
                    inBlock = false
                } else {
                    buffer = remaining
                    remaining = ""
                }
            } else {
                if let startRange = remaining.range(of: "<think>") {
                    output += String(remaining[remaining.startIndex..<startRange.lowerBound])
                    remaining = String(remaining[startRange.upperBound...])
                    inBlock = true
                } else {
                    let partial = "<think>"
                    var partialMatch = false
                    for i in 1...min(partial.count, remaining.count) {
                        let suffix = String(partial.prefix(i))
                        if remaining.hasSuffix(suffix) {
                            output += String(remaining.dropLast(suffix.count))
                            buffer = suffix
                            partialMatch = true
                            break
                        }
                    }
                    if !partialMatch {
                        output += remaining
                    }
                    remaining = ""
                }
            }
        }

        return output
    }

    // MARK: - System prompt

    static func buildSystemPrompt(facts: [(key: String, content: String)] = []) -> String {
        let df = DateFormatter()
        df.locale = Locale(identifier: "it_IT")
        df.dateFormat = "EEEE d MMMM yyyy"
        let today = df.string(from: Date())

        var prompt = """
        Sei Jarvis, un assistente AI personale che gira completamente sul dispositivo dell'utente. \
        Sei preciso, conciso e proattivo. Oggi è \(today).

        Rispondi sempre in italiano a meno che l'utente non scriva in un'altra lingua. \
        Tieni le risposte brevi e dirette. Non usare formattazione markdown, scrivi in testo semplice.

        Quando hai bisogno di informazioni in tempo reale (ora, eventi, posizione), usa sempre i tool disponibili. \
        Non indovinare mai l'ora o la data — usa get_current_datetime. \
        Non rispondere "non so" se puoi usare un tool per trovare la risposta.
        """

        if !facts.isEmpty {
            prompt += "\n\n## Informazioni note sull'utente:\n"
            for fact in facts {
                prompt += "- \(fact.key): \(fact.content)\n"
            }
        }

        return prompt
    }
}

// MARK: - Errors

enum JarvisError: LocalizedError {
    case modelNotLoaded
    case generationFailed(String)
    case toolFailed(tool: String, reason: String)
    case permissionDenied(String)
    case outOfMemory

    var errorDescription: String? {
        switch self {
        case .modelNotLoaded:
            return "Modello non caricato. Avvia prima il download."
        case .generationFailed(let msg):
            return "Errore nella generazione: \(msg)"
        case .toolFailed(let tool, let reason):
            return "Tool '\(tool)' fallito: \(reason)"
        case .permissionDenied(let feature):
            return "Permesso negato per: \(feature)"
        case .outOfMemory:
            return "Memoria esaurita. Riavvia l'app."
        }
    }
}
