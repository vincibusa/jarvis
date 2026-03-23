import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(LLMService.self) private var llm
    @Environment(\.modelContext) private var modelContext
    @State private var toolsConfigured = false

    var body: some View {
        Group {
            switch llm.state {
            case .ready, .generating:
                ChatView()
            default:
                ModelDownloadView()
            }
        }
        .preferredColorScheme(.dark)
        .task {
            // Auto-load if model is already downloaded
            if llm.isModelDownloaded {
                await llm.loadModel()
            }
        }
        .onChange(of: llm.state) { _, newState in
            if case .ready = newState, !toolsConfigured {
                configureTools()
            }
        }
    }

    private func configureTools() {
        let memoryService = MemoryService(modelContext: modelContext)
        let router = ToolRouter(memoryService: memoryService)
        llm.configureTools(router: router)

        // Inject stored memory facts into system prompt
        let facts = memoryService.factsForPrompt()
        if !facts.isEmpty {
            llm.updateSystemPrompt(LLMService.buildSystemPrompt(facts: facts))
        }

        toolsConfigured = true
    }
}
