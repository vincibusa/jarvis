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
    private var generationCancelled = false

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
                maxTokens: 2048,
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
            let config = ModelConfiguration(id: Self.modelID, toolCallFormat: .xmlFunction)

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
        MLX.GPU.clearCache()
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
        generationCancelled = false

        return AsyncThrowingStream { [weak self] continuation in
            Task { [weak self] in
                guard let self else { continuation.finish(); return }
                var thinkBuffer = ""
                var inThinkBlock = false
                var tokenCount = 0
                let startTime = Date()

                do {
                    // Multi-tool loop: continue executing tool calls until the model
                    // produces a plain text response (max 8 tool calls, with duplicate/loop guards)
                    var nextPrompt: String? = prompt
                    var remainingToolCalls = 8
                    var lastToolCallKey: String? = nil   // Exact duplicate detection
                    var lastToolName: String? = nil      // Consecutive same-tool detection
                    var consecutiveSameToolCount = 0

                    while let currentPrompt = nextPrompt {
                        nextPrompt = nil
                        var detectedToolCall: ToolCall? = nil

                        // Check if a reset was requested while we were awaiting a tool result
                        if self.generationCancelled {
                            continuation.finish()
                            return
                        }

                        for try await generation in session.streamDetails(to: currentPrompt, images: [], videos: []) {
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

                        // If a tool call was detected, execute it and loop again
                        if let toolCall = detectedToolCall, let router = self.toolRouter, remainingToolCalls > 0 {
                            remainingToolCalls -= 1
                            let name = toolCall.function.name
                            let args = toolCall.function.arguments.mapValues { $0.anyValue }

                            // Break on exact duplicate call (same tool + same args)
                            let callKey = "\(name):\(toolCall.function.arguments.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: ","))"
                            if callKey == lastToolCallKey {
                                print("⚠️ [Jarvis] Loop rilevato (\(name) args identici), interrompo")
                                break
                            }
                            lastToolCallKey = callKey

                            // Break on 3+ consecutive calls to the same tool (different args = model spinning)
                            if name == lastToolName {
                                consecutiveSameToolCount += 1
                                if consecutiveSameToolCount >= 2 {
                                    print("⚠️ [Jarvis] Loop rilevato (\(name) chiamato \(consecutiveSameToolCount + 1) volte di fila), interrompo")
                                    break
                                }
                            } else {
                                consecutiveSameToolCount = 0
                                lastToolName = name
                            }

                            let toolResult: String
                            do {
                                toolResult = try await router.execute(name: name, arguments: args)
                                print("✅ [Jarvis] Tool result: \(toolResult.prefix(200))")
                            } catch {
                                print("❌ [Jarvis] Tool error: \(error)")
                                toolResult = "Errore: \(error.localizedDescription)"
                            }

                            // Feed result back and continue the loop
                            thinkBuffer = ""
                            inThinkBlock = false
                            nextPrompt = "[Risultato \(name)]: \(toolResult)"
                        }
                        // If no tool call or limit reached, the loop ends naturally
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

    func resetConversation(facts: [(key: String, content: String)] = []) {
        guard let container = modelContainer else { return }
        generationCancelled = true
        streamingText = ""
        let tools: [ToolSpec]? = toolRouter != nil ? ToolDefinitions.allToolSpecs : nil
        let session = ChatSession(
            container,
            instructions: Self.buildSystemPrompt(facts: facts),
            generateParameters: GenerateParameters(
                maxTokens: 2048,
                temperature: 0.7,
                topP: 0.9,
                repetitionPenalty: 1.1
            ),
            tools: tools
        )
        self.chatSession = session
    }

    /// Resets the session with a compacted summary instead of full history.
    /// Used by ContextCompactor when the conversation grows too long.
    func resetWithCompactedContext(
        conversationSummary: String,
        facts: [(key: String, content: String)] = []
    ) {
        guard let container = modelContainer else { return }
        generationCancelled = true
        let tools: [ToolSpec]? = toolRouter != nil ? ToolDefinitions.allToolSpecs : nil
        let session = ChatSession(
            container,
            instructions: Self.buildSystemPrompt(facts: facts, lastConversationSummary: conversationSummary),
            generateParameters: GenerateParameters(
                maxTokens: 2048,
                temperature: 0.7,
                topP: 0.9,
                repetitionPenalty: 1.1
            ),
            tools: tools
        )
        self.chatSession = session
    }

    func updateSystemPrompt(_ prompt: String) {
        chatSession?.instructions = prompt
    }

    // MARK: - Download check

    var isModelDownloaded: Bool {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let parts = Self.modelID.components(separatedBy: "/")
        let org  = parts.first ?? ""
        let repo = parts.last  ?? Self.modelID
        let fm = FileManager.default

        // Actual layout used by swift-transformers Hub: Caches/huggingface/hub/models--<org>--<repo>
        let hubDir = caches.appendingPathComponent("huggingface").appendingPathComponent("hub")
        let modelDir = hubDir.appendingPathComponent("models--\(org)--\(repo)")
        return fm.fileExists(atPath: modelDir.path)
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

    static func buildSystemPrompt(
        facts: [(key: String, content: String)] = [],
        lastConversationSummary: String? = nil
    ) -> String {
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
        - Per informazioni recenti, notizie, o fatti ESTERNI: usa web_search.
          NON usare web_search per leggere documenti già importati dall'utente.
        - Per inviare email: usa send_email con destinatario, oggetto e corpo.
        - Per trascrivere o riassumere file audio: usa transcribe_audio o summarize_audio.
        - Per leggere il CONTENUTO di un documento importato: usa search_documents con una query descrittiva.
          Esempio: dopo list_documents hai visto "CV.pdf" → chiama search_documents("esperienza lavorativa") per leggerlo.
        - Per vedere quali documenti sono disponibili: usa list_documents.
        - IMPORTANTE: se l'utente ti ha già caricato un documento, NON cercarlo su web. Leggi il documento con search_documents.

        MEMORIA:
        - Usa 'remember' PROATTIVAMENTE per salvare informazioni importanti sull'utente:
          nome, preferenze, abitudini, persone menzionate, lavoro, interessi, progetti.
        - Se l'utente menziona qualcosa di personale, memorizzalo SENZA che te lo chieda.
        - Usa 'recall' PRIMA di rispondere se pensi ci sia un ricordo rilevante.
        - Non chiedere "vuoi che lo ricordi?" — memorizza e basta.
        - Se l'utente carica un documento (CV, bio, note personali) e dice che contiene i suoi dati,
          chiama search_documents per leggerne il contenuto, poi estrai e salva con 'remember'
          tutti i fatti chiave: nome, professione, competenze, esperienze, contatti, ecc.
        - Per domande personali (es. "che lavoro faccio?", "dove vivo?") chiama PRIMA 'recall'.
          Se recall non trova l'informazione specifica (restituisce solo il nome o niente),
          chiama search_documents con una query pertinente per cercare nei documenti caricati.
          NON ripetere recall con la stessa query se non ha trovato quello che serve.

        REGOLE ANTI-LOOP (OBBLIGATORIE):
        - NON chiamare 'recall' più di 2 volte in una singola risposta.
        - NON chiamare 'recall' dopo aver già ricevuto il risultato di 'search_documents'.
          Se search_documents ha restituito contenuto, USALO direttamente per rispondere.
        - Dopo 'search_documents': salva i fatti con 'remember', poi rispondi. STOP.
        - NON variare leggermente la query di recall sperando in risultati diversi:
          se il primo recall non trova, usa search_documents oppure rispondi con quello che sai.
        """

        // Budget: max 10 fatti più recenti (non tutti, per non gonfiare il prompt)
        if !facts.isEmpty {
            prompt += "\n\nInformazioni utente note:\n"
            for fact in facts.prefix(10) {
                prompt += "- \(fact.key): \(fact.content)\n"
            }
        }

        // Riepilogo ultima conversazione (~200 token max)
        if let summary = lastConversationSummary, !summary.isEmpty {
            prompt += "\n\nUltima conversazione:\n\(summary)"
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
