import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(LLMService.self) private var llm
    @Environment(\.modelContext) private var modelContext
    @State private var toolsConfigured = false
    @State private var imagePickerCoordinator = ImagePickerCoordinator()
    @State private var emailComposerCoordinator = EmailComposerCoordinator()
    @State private var audioPickerCoordinator = AudioPickerCoordinator()
    @State private var documentShareCoordinator = DocumentShareCoordinator()
    @State private var embeddingService = EmbeddingService()
    @State private var documentService: DocumentService?

    var body: some View {
        Group {
            switch llm.state {
            case .error:
                ModelDownloadView()
            default:
                if llm.state == .ready || llm.state == .generating || llm.isModelDownloaded {
                    ChatView()
                        .environment(imagePickerCoordinator)
                        .environment(audioPickerCoordinator)
                        .environment(emailComposerCoordinator)
                        .environment(documentShareCoordinator)
                        .environment(\.documentService, documentService)
                } else {
                    ModelDownloadView()
                }
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

        // VectorStore dedicated to memory (separate from document store)
        let memoryVectorStore = VectorStore(path: Self.memoryVectorStoreURL())

        let router = ToolRouter(
            memoryService: memoryService,
            embeddingService: embeddingService,
            memoryVectorStore: memoryVectorStore,
            imagePickerCoordinator: imagePickerCoordinator,
            emailComposerCoordinator: emailComposerCoordinator,
            audioPickerCoordinator: audioPickerCoordinator
        )

        // Configure RAG / Document system
        let docService = DocumentService(
            embeddingService: embeddingService,
            modelContext: modelContext
        )
        let documentTool = DocumentTool(documentService: docService)
        router.configureDocuments(documentTool: documentTool)
        self.documentService = docService

        // Configure document creation (PDF / Word / Excel)
        let creationTool = DocumentCreationTool(coordinator: documentShareCoordinator)
        router.configureDocumentCreation(tool: creationTool)

        llm.configureTools(router: router)
        JarvisEngine.shared.configure(llm: llm)

        // Inject stored memory facts into system prompt
        let facts = memoryService.factsForPrompt()
        llm.updateSystemPrompt(LLMService.buildSystemPrompt(facts: facts))

        // Live refresh: when LLM calls remember(), update system prompt immediately
        router.memoryToolRef.onFactsChanged = { [weak llm] in
            let updated = memoryService.factsForPrompt()
            llm?.updateSystemPrompt(LLMService.buildSystemPrompt(facts: updated))
        }

        // Embedding model loads lazily (on first recall/remember call)
        // to avoid holding ~300 MB resident alongside the LLM.

        toolsConfigured = true
    }

    private static func memoryVectorStoreURL() -> URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent("jarvis_memory.sqlite3")
    }
}
