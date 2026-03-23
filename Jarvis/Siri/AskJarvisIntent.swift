import AppIntents

struct AskJarvisIntent: AppIntent {
    static var title: LocalizedStringResource = "Chiedi a Jarvis"
    static var description: IntentDescription = IntentDescription(
        "Fai una domanda a Jarvis, il tuo assistente AI personale on-device",
        categoryName: "Assistente"
    )

    /// Open the app — the 1.4 GB LLM requires the app's GPU context.
    /// The intent returns immediately; the app processes the question internally.
    /// This avoids Siri's ~30s timeout which a local LLM always exceeds.
    static var openAppWhenRun: Bool = true

    @Parameter(title: "Domanda", description: "Cosa vuoi chiedere a Jarvis?")
    var question: QuestionEntity

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let engine = JarvisEngine.shared

        guard engine.isModelDownloaded else {
            return .result(dialog: IntentDialog(
                "Il modello AI non è ancora scaricato. Apri Jarvis prima di usarlo con Siri."
            ))
        }

        // Post the question to the app — ChatView observes pendingQuestion and sends it.
        // We return immediately so Siri doesn't time out waiting for the LLM response.
        engine.pendingQuestion = question.id

        return .result(dialog: IntentDialog(
            "Ho passato la domanda a Jarvis. Controlla l'app per la risposta."
        ))
    }
}
