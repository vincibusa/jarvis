import SwiftUI
import SwiftData

struct ChatView: View {
    @Environment(LLMService.self) private var llm
    @Environment(\.modelContext) private var modelContext

    @State private var conversation: Conversation = Conversation()
    @State private var inputText: String = ""
    @State private var isGenerating = false
    @State private var scrollProxy: ScrollViewProxy? = nil
    @State private var latestMessageID: UUID? = nil
    @State private var showSettings = false
    @State private var speechService = SpeechService()
    @State private var isListening = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            JarvisHeader(state: llm.state) {
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
        .onAppear {
            modelContext.insert(conversation)
        }
        .task {
            _ = await speechService.requestAuthorization()
        }
    }

    // MARK: - Input bar

    private var inputBar: some View {
        HStack(spacing: 10) {
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
        guard !text.isEmpty, !isGenerating else { return }

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
                assistantMsg.content = "Mi dispiace, si è verificato un errore."
            }

            // Title conversation after first exchange
            if conversation.title == "Nuova conversazione" && !assistantMsg.content.isEmpty {
                conversation.title = String(text.prefix(40))
            }

            // Speak response
            if !assistantMsg.content.isEmpty {
                await speechService.speak(assistantMsg.content)
            }

            try? modelContext.save()
            isGenerating = false
        }
    }

    private func scrollToBottom(proxy: ScrollViewProxy) {
        if let lastMsg = conversation.sortedMessages.last {
            withAnimation(.easeOut(duration: 0.2)) {
                proxy.scrollTo(lastMsg.id, anchor: .bottom)
            }
        }
    }
}
