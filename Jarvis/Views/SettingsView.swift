import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(LLMService.self) private var llm

    @State private var userName: String = ""
    @State private var showClearConfirm = false

    // MARK: - Computed

    private var memoryService: MemoryService {
        MemoryService(modelContext: modelContext)
    }

    private var factCount: Int {
        memoryService.allFacts().count
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            List {

                // MARK: Profilo
                Section("Profilo") {
                    HStack {
                        Text("Nome")
                            .foregroundStyle(.secondary)
                        Spacer()
                        TextField("Il tuo nome", text: $userName)
                            .multilineTextAlignment(.trailing)
                            .submitLabel(.done)
                            .onSubmit {
                                let trimmed = userName.trimmingCharacters(in: .whitespacesAndNewlines)
                                guard !trimmed.isEmpty else { return }
                                memoryService.remember(key: "nome_utente", content: trimmed)
                            }
                    }
                }

                // MARK: Modello
                Section("Modello") {
                    LabeledContent("Modello", value: "Qwen3.5-2B (4-bit)")
                    LabeledContent("Dimensione", value: "~1.4 GB")
                    LabeledContent("Privacy", value: "100% on-device")
                    if llm.tokensPerSecond > 0 {
                        LabeledContent(
                            "Velocità",
                            value: String(format: "%.1f tok/s", llm.tokensPerSecond)
                        )
                    }
                }

                // MARK: Memoria
                Section("Memoria") {
                    LabeledContent("Fatti memorizzati", value: "\(factCount)")

                    Button(role: .destructive) {
                        showClearConfirm = true
                    } label: {
                        Label("Cancella tutta la memoria", systemImage: "trash")
                    }
                }

                // MARK: Conversazione
                Section("Conversazione") {
                    Button {
                        let facts = memoryService.factsForPrompt()
                        llm.resetConversation(facts: facts)
                        dismiss()
                    } label: {
                        Label("Nuova conversazione", systemImage: "plus.bubble")
                    }
                }

                // MARK: Info
                Section("Info") {
                    LabeledContent("Versione", value: "1.0.0")
                    LabeledContent("Runtime", value: "MLX Swift")
                }
            }
            .navigationTitle("Impostazioni")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(JarvisTheme.accent)
                    }
                }
            }
            .onAppear {
                loadStoredName()
            }
            .confirmationDialog(
                "Cancella memoria",
                isPresented: $showClearConfirm,
                titleVisibility: .visible
            ) {
                Button("Cancella tutto", role: .destructive) {
                    memoryService.clearAllMemory()
                }
                Button("Annulla", role: .cancel) {}
            } message: {
                Text("Tutti i fatti memorizzati verranno eliminati. Questa azione è irreversibile.")
            }
            .preferredColorScheme(.dark)
        }
    }

    // MARK: - Helpers

    private func loadStoredName() {
        let facts = memoryService.allFacts()
        if let nameFact = facts.first(where: { $0.key == "nome_utente" }) {
            userName = nameFact.content
        }
    }
}

// MARK: - Preview

#Preview {
    SettingsView()
        .environment(LLMService())
        .modelContainer(for: [MemoryFact.self, Conversation.self, Message.self], inMemory: true)
}
