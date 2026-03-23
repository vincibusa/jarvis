import SwiftUI
import SwiftData

struct ConversationListView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \Conversation.updatedAt, order: .reverse)
    private var conversations: [Conversation]

    var body: some View {
        NavigationStack {
            Group {
                if conversations.isEmpty {
                    emptyState
                } else {
                    List {
                        ForEach(conversations) { conv in
                            NavigationLink {
                                ConversationDetailView(conversation: conv)
                            } label: {
                                conversationRow(conv)
                            }
                            .listRowBackground(Color.black)
                        }
                        .onDelete(perform: deleteConversations)
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
            .background(JarvisTheme.background)
            .navigationTitle("Storico")
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
            .preferredColorScheme(.dark)
        }
    }

    // MARK: - Row

    private func conversationRow(_ conv: Conversation) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(conv.title)
                .font(.body)
                .foregroundStyle(.white)
                .lineLimit(1)

            HStack {
                Text(conv.updatedAt, style: .relative)
                    .font(.caption)
                    .foregroundStyle(.gray)
                Spacer()
                Text("\(conv.messages.count) messaggi")
                    .font(.caption)
                    .foregroundStyle(.gray)
            }

            if let lastMsg = conv.sortedMessages.last(where: { $0.isAssistant }) {
                Text(lastMsg.content)
                    .font(.caption)
                    .foregroundStyle(.gray.opacity(0.7))
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 48))
                .foregroundStyle(JarvisTheme.accent.opacity(0.4))
            Text("Nessuna conversazione salvata")
                .font(.callout)
                .foregroundStyle(.gray)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Delete

    private func deleteConversations(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(conversations[index])
        }
        try? modelContext.save()
    }
}
