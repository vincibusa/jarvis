import Foundation
import Observation

/// Singleton bridge that exposes LLMService to AppIntents (Siri).
/// The intent runs in the app's process (openAppWhenRun: true), so this
/// singleton is shared between the app UI and the intent.
///
/// Design: Siri intent returns immediately and posts the question here.
/// The app observes `pendingQuestion` and sends it to the LLM normally.
/// This avoids Siri's ~30s timeout which a 1.4 GB on-device LLM always exceeds.
@Observable
@MainActor
final class JarvisEngine {

    static let shared = JarvisEngine()

    private(set) var llmService: LLMService?

    /// Set by AskJarvisIntent; observed by ChatView to auto-send the question.
    var pendingQuestion: String? = nil

    private init() {}

    // MARK: - Configuration (called from JarvisApp)

    func configure(llm: LLMService) {
        self.llmService = llm
    }

    // MARK: - State

    var isModelDownloaded: Bool {
        llmService?.isModelDownloaded ?? false
    }
}
