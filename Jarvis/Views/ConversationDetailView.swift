import SwiftUI
import SwiftData

struct ConversationDetailView: View {
    let conversation: Conversation

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(conversation.sortedMessages, id: \.id) { message in
                        if message.isUser || message.isAssistant {
                            MessageBubble(message: message)
                                .padding(.horizontal, 12)
                                .id(message.id)
                        }
                    }
                }
                .padding(.vertical, 12)
            }
            .onAppear {
                if let last = conversation.sortedMessages.last {
                    proxy.scrollTo(last.id, anchor: .bottom)
                }
            }
        }
        .background(JarvisTheme.background)
        .navigationTitle(conversation.title)
        .navigationBarTitleDisplayMode(.inline)
        .preferredColorScheme(.dark)
    }
}
