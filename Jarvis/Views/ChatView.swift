import SwiftUI
import SwiftData

struct ChatView: View {
    @Environment(LLMService.self) private var llm
    @Environment(\.modelContext) private var modelContext
    @Environment(ImagePickerCoordinator.self) private var imagePickerCoordinator
    @Environment(AudioPickerCoordinator.self) private var audioPickerCoordinator
    @Environment(EmailComposerCoordinator.self) private var emailComposerCoordinator
    @Environment(\.documentService) private var documentService

    @State private var conversation: Conversation = Conversation()
    @State private var inputText: String = ""
    @State private var isGenerating = false
    @State private var scrollProxy: ScrollViewProxy? = nil
    @State private var latestMessageID: UUID? = nil
    @State private var showSettings = false
    @State private var showDocuments = false
    @State private var showHistory = false
    @State private var speechService = SpeechService()
    @State private var isListening = false

    // Sheet state derived from coordinator.pendingRequest
    @State private var showImagePicker = false
    @State private var showDocumentScanner = false
    @State private var activePicker: ImagePickerCoordinator.PickerSource? = nil
    @State private var showAudioPicker = false
    @State private var showEmailComposer = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            JarvisHeader(state: llm.state, onHistory: {
                showHistory = true
            }) {
                showSettings = true
            }

            // Messages
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 10) {
                        if conversation.sortedMessages.isEmpty {
                            emptyState
                        }

                        ForEach(conversation.sortedMessages, id: \.id) { message in
                            MessageBubble(message: message)
                                .padding(.horizontal, 12)
                                .id(message.id)
                        }

                        // Thinking indicator
                        if isGenerating && conversation.sortedMessages.last?.isAssistant == true {
                            // Already showing streaming text
                        } else if isGenerating {
                            HStack {
                                ThinkingIndicator()
                                    .padding(.horizontal, 12)
                                Spacer()
                            }
                            .id("thinking")
                        }
                    }
                    .padding(.vertical, 12)
                }
                .onAppear { scrollProxy = proxy }
                .onChange(of: conversation.messages.count) { _, _ in
                    scrollToBottom(proxy: proxy)
                }
                .onChange(of: llm.streamingText) { _, _ in
                    scrollToBottom(proxy: proxy)
                }
            }

            Divider()
                .background(Color.gray.opacity(0.2))

            // Input area
            inputBar
        }
        .background(JarvisTheme.background)
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        .sheet(isPresented: $showHistory) {
            ConversationListView()
        }
        .sheet(isPresented: $showDocuments) {
            if let docService = documentService {
                DocumentListView(documentService: docService)
            }
        }
        .sheet(isPresented: $showImagePicker, onDismiss: {
            // If user dismissed sheet without picking, cancel the pending request
            if let source = activePicker, source != .documentScanner {
                imagePickerCoordinator.cancel()
            }
            activePicker = nil
        }) {
            if let source = activePicker {
                ImagePickerView(source: source) { cgImage in
                    imagePickerCoordinator.deliverImage(cgImage)
                    showImagePicker = false
                    activePicker = nil
                }
            }
        }
        .sheet(isPresented: $showDocumentScanner, onDismiss: {
            if activePicker == .documentScanner {
                imagePickerCoordinator.cancel()
            }
            activePicker = nil
        }) {
            DocumentScannerView { pages in
                // Deliver the first page; multi-page results are surfaced via analyzeDocument
                imagePickerCoordinator.deliverImage(pages.first)
                showDocumentScanner = false
                activePicker = nil
            }
        }
        .onAppear {
            modelContext.insert(conversation)
        }
        .onDisappear {
            saveConversationSummary()
            speechService.stopSpeaking()
            if isListening {
                _ = speechService.stopListening()
                isListening = false
            }
        }
        .task {
            _ = await speechService.requestAuthorization()
        }
        .sheet(isPresented: $showAudioPicker, onDismiss: {
            audioPickerCoordinator.cancel()
        }) {
            AudioPickerView { url in
                audioPickerCoordinator.deliverFile(url)
                showAudioPicker = false
            }
        }
        .onChange(of: imagePickerCoordinator.pendingRequest) { _, newRequest in
            guard let request = newRequest else { return }
            activePicker = request
            switch request {
            case .camera, .photoLibrary:
                showImagePicker = true
            case .documentScanner:
                showDocumentScanner = true
            }
        }
        .onChange(of: audioPickerCoordinator.isPicking) { _, isPicking in
            if isPicking {
                showAudioPicker = true
            }
        }
        .sheet(isPresented: $showEmailComposer, onDismiss: {
            emailComposerCoordinator.deliverResult(sent: false)
        }) {
            if let email = emailComposerCoordinator.pendingEmail {
                EmailComposerView(
                    to: email.to,
                    subject: email.subject,
                    body: email.body
                ) { sent in
                    emailComposerCoordinator.deliverResult(sent: sent)
                    showEmailComposer = false
                }
            }
        }
        .onChange(of: emailComposerCoordinator.hasPendingEmail) { _, hasPending in
            if hasPending {
                showEmailComposer = true
            }
        }
        // Handle questions arriving from Siri (AskJarvisIntent sets pendingQuestion)
        .onChange(of: JarvisEngine.shared.pendingQuestion) { _, question in
            guard let q = question, !q.isEmpty else { return }
            JarvisEngine.shared.pendingQuestion = nil
            inputText = q
            sendMessage()
        }
    }

    // MARK: - Input bar

    private var inputBar: some View {
        HStack(spacing: 10) {
            // Paperclip button — only visible when document service is available
            if documentService != nil {
                Button {
                    showDocuments = true
                } label: {
                    Image(systemName: "paperclip")
                        .font(.title3)
                        .foregroundStyle(.gray)
                        .frame(width: 36, height: 36)
                }
            }

            TextField("Messaggio...", text: $inputText, axis: .vertical)
                .font(.body)
                .foregroundStyle(.white)
                .tint(JarvisTheme.accent)
                .lineLimit(5)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(JarvisTheme.inputBackground)
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .onSubmit { sendMessage() }

            if inputText.isEmpty {
                VoiceButton(isListening: $isListening, onStart: {
                    speechService.startListening()
                }, onStop: {
                    let transcript = speechService.stopListening()
                    if !transcript.isEmpty {
                        inputText = transcript
                        sendMessage()
                    }
                })
                .frame(width: 52, height: 52)
            } else {
                Button(action: sendMessage) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                        .foregroundStyle(JarvisTheme.accent)
                        .frame(width: 44, height: 44)
                }
                .disabled(isGenerating)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.black)
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "waveform")
                .font(.system(size: 48))
                .foregroundStyle(JarvisTheme.accent.opacity(0.5))

            Text("Ciao, sono Jarvis.")
                .font(.title3)
                .foregroundStyle(.white)

            Text("Puoi chiedermi l'orario, creare eventi,\nricordare informazioni e molto altro.")
                .font(.callout)
                .foregroundStyle(.gray)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 80)
        .padding(.horizontal, 40)
    }

    // MARK: - Send message

    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isGenerating, llm.state == .ready else { return }

        inputText = ""
        isGenerating = true

        // Add user message
        let userMsg = Message(role: .user, content: text)
        conversation.messages.append(userMsg)
        conversation.updatedAt = Date()

        // Create empty assistant message for streaming
        let assistantMsg = Message(role: .assistant, content: "")
        conversation.messages.append(assistantMsg)

        Task {
            let stream = llm.send(prompt: text)

            do {
                for try await chunk in stream {
                    assistantMsg.content += chunk
                }
            } catch {
                print("❌ [Jarvis] Errore generazione: \(error)")
                print("❌ [Jarvis] Errore dettaglio: \(error.localizedDescription)")
                assistantMsg.content = "Mi dispiace, si è verificato un errore."
            }

            // Title conversation after first exchange
            if conversation.title == "Nuova conversazione" && !assistantMsg.content.isEmpty {
                conversation.title = String(text.prefix(40))
            }

            try? modelContext.save()
            isGenerating = false

            // Compact context if conversation is getting too long
            let compactor = ContextCompactor(
                llmService: llm,
                memoryService: MemoryService(modelContext: modelContext)
            )
            compactor.compactIfNeeded(conversation: conversation)
        }
    }

    // MARK: - Summary helpers

    private func saveConversationSummary() {
        guard conversation.summary == nil,
              !conversation.sortedMessages.isEmpty else { return }
        conversation.summary = ContextCompactor.buildSummary(from: conversation.sortedMessages)
        try? modelContext.save()
    }

    private func scrollToBottom(proxy: ScrollViewProxy) {
        if let lastMsg = conversation.sortedMessages.last {
            withAnimation(.easeOut(duration: 0.2)) {
                proxy.scrollTo(lastMsg.id, anchor: .bottom)
            }
        }
    }
}
