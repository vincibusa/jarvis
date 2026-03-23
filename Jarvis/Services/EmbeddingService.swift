import Foundation
import MLX
import MLXEmbedders
import MLXLMCommon
import Observation
import Tokenizers

@Observable
@MainActor
final class EmbeddingService {

    // MARK: - State

    enum State: Equatable {
        case idle
        case downloading(progress: Double)
        case loading
        case ready
        case error(String)
    }

    var state: State = .idle

    // The embedding model container (actor-isolated for thread safety)
    private var modelContainer: MLXEmbedders.ModelContainer?

    // multilingual-e5-small supports 100+ languages including Italian
    static let modelConfig = ModelConfiguration.multilingual_e5_small

    // MARK: - Load / Unload

    func loadModel() async {
        guard case .idle = state else { return }
        state = .downloading(progress: 0)

        do {
            let container = try await loadModelContainer(
                hub: defaultHubApi,
                configuration: Self.modelConfig
            ) { [weak self] progress in
                Task { @MainActor [weak self] in
                    self?.state = .downloading(progress: progress.fractionCompleted)
                }
            }
            self.modelContainer = container
            state = .ready
        } catch {
            state = .error(error.localizedDescription)
        }
    }

    /// Release the model from memory to free GPU/RAM resources.
    /// Calls MLX.GPU.clearCache() to actually flush the Metal memory pool.
    func unloadModel() {
        modelContainer = nil
        state = .idle
        MLX.GPU.clearCache()
    }

    // MARK: - Embed

    /// Embed a single text string, returning a Float vector.
    /// Auto-loads the model if not yet loaded.
    func embed(text: String) async throws -> [Float] {
        if case .idle = state {
            await loadModel()
        }
        guard let container = modelContainer else {
            throw EmbeddingError.modelNotLoaded
        }

        let result = try await container.perform { model, tokenizer, pooler -> [Float] in
            // Tokenize
            let encoded = tokenizer.encode(text: text)
            let inputIds = MLXArray(encoded.map { Int32($0) })[.newAxis]

            // Forward pass
            let output = model(inputIds, positionIds: nil, tokenTypeIds: nil, attentionMask: nil)

            // Pool and normalize (mean pooling with L2 normalization for E5 models)
            let pooled = pooler(output, mask: nil, normalize: true)

            // Evaluate before leaving actor (MLXArray is not Sendable)
            eval(pooled)

            return pooled.asArray(Float.self)
        }

        return result
    }

    /// Embed multiple texts in one call.
    func embedBatch(texts: [String]) async throws -> [[Float]] {
        var results: [[Float]] = []
        for text in texts {
            let embedding = try await embed(text: text)
            results.append(embedding)
        }
        return results
    }

    // MARK: - Errors

    enum EmbeddingError: LocalizedError {
        case modelNotLoaded

        var errorDescription: String? {
            switch self {
            case .modelNotLoaded:
                return "Modello di embedding non caricato."
            }
        }
    }
}
