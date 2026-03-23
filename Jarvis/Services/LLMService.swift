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

        let session = ChatSession(
            container,
            instructions: Self.buildSystemPrompt(),
            generateParameters: GenerateParameters(
                maxTokens: 1024,
                temperature: 0.7,
                topP: 0.9,
                repetitionPenalty: 1.1
            ),
            tools: tools
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
    /// Detects tool calls via streamDetails(), executes them, and feeds the result back.
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
                    // Use streamDetails to detect tool calls
                    var detectedToolCall: ToolCall? = nil

                    for try await generation in session.streamDetails(to: prompt, images: [], videos: []) {
                        if let chunk = generation.chunk {
                            tokenCount += 1
                            let filtered = self.processChunk(
                                chunk,
                                buffer: &thinkBuffer,
                                inBlock: &inThinkBlock
                            )
                            if !filtered.isEmpty {
                                await MainActor.run { self.streamingText += filtered }
                                continuation.yield(filtered)
                            }
                        } else if let toolCall = generation.toolCall {
                            detectedToolCall = toolCall
                            print("🔧 [Jarvis] Tool call rilevata: \(toolCall.function.name)")
                            print("🔧 [Jarvis] Argomenti: \(toolCall.function.arguments)")
                        }
                    }

                    // Execute tool call and feed result back to model
                    if let toolCall = detectedToolCall, let router = self.toolRouter {
                        let name = toolCall.function.name
                        let args = toolCall.function.arguments.mapValues { $0.anyValue }

                        let toolResult: String
                        do {
                            toolResult = try await router.execute(name: name, arguments: args)
                            print("✅ [Jarvis] Tool result: \(toolResult.prefix(200))")
                        } catch {
                            print("❌ [Jarvis] Tool error: \(error)")
                            toolResult = "Errore: \(error.localizedDescription)"
                        }

                        // Feed result back as user message (Qwen3.5 template doesn't support .tool role)
                        let followUp = "[Risultato \(name)]: \(toolResult)"
                        thinkBuffer = ""
                        inThinkBlock = false

                        for try await generation in session.streamDetails(to: followUp, images: [], videos: []) {
                            if let chunk = generation.chunk {
                                tokenCount += 1
                                let filtered = self.processChunk(
                                    chunk,
                                    buffer: &thinkBuffer,
                                    inBlock: &inThinkBlock
                                )
                                if !filtered.isEmpty {
                                    await MainActor.run { self.streamingText += filtered }
                                    continuation.yield(filtered)
                                }
                            }
                            // Ignore nested tool calls to avoid infinite loops
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
                    print("❌ [Jarvis] Stream error: \(error)")
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
        let now = Date()

        let dateFmt = DateFormatter()
        dateFmt.locale = Locale(identifier: "it_IT")
        dateFmt.timeZone = TimeZone.current
        dateFmt.dateFormat = "EEEE d MMMM yyyy"
        let todayHuman = dateFmt.string(from: now)

        let isoFmt = DateFormatter()
        isoFmt.locale = Locale(identifier: "en_US_POSIX")
        isoFmt.timeZone = TimeZone.current
        isoFmt.dateFormat = "yyyy-MM-dd'T'HH:mm"
        let nowISO = isoFmt.string(from: now)

        let tomorrowISO = isoFmt.string(from: Calendar.current.date(byAdding: .day, value: 1, to: now)!)

        var prompt = """
        Sei Jarvis, un assistente AI personale sul dispositivo dell'utente. \
        Sei preciso, conciso e proattivo.

        DATA E ORA CORRENTE: \(todayHuman), \(nowISO)
        DOMANI: \(String(tomorrowISO.prefix(10)))

        Rispondi in italiano. Risposte brevi, testo semplice, no markdown.

        REGOLE TOOL:
        - Per ora/data: usa get_current_datetime.
        - Per creare eventi: usa create_event con start_date in formato yyyy-MM-dd'T'HH:mm.
        - "domani" = \(String(tomorrowISO.prefix(10))), "oggi" = \(String(nowISO.prefix(10))).
        - Non inventare date o orari. Calcola sempre partendo dalla data corrente sopra.
        - Non rispondere "non so" se puoi usare un tool.
        """

        if !facts.isEmpty {
            prompt += "\n\nInformazioni utente:\n"
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
