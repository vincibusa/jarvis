import SwiftUI
import SwiftData
import MLX

@main
struct JarvisApp: App {

    @State private var llmService = LLMService()
    private let swiftDataContainer: ModelContainer

    init() {
        // Limit MLX GPU cache to avoid memory pressure
        GPU.set(cacheLimit: 20 * 1024 * 1024)  // 20 MB

        // SwiftData container for conversations, messages, memories
        let schema = Schema([
            Conversation.self,
            Message.self,
            MemoryFact.self,
            Document.self,
        ])
        do {
            swiftDataContainer = try ModelContainer(
                for: schema,
                configurations: ModelConfiguration(isStoredInMemoryOnly: false)
            )
        } catch {
            fatalError("SwiftData container init failed: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(llmService)
                .modelContainer(swiftDataContainer)
                .preferredColorScheme(.dark)
                .onAppear {
                    // Register synchronously on appear (before any Siri intent can call perform())
                    JarvisEngine.shared.configure(llm: llmService)
                }
        }
    }
}
