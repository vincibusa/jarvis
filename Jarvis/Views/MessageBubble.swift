import SwiftUI

struct MessageBubble: View {
    let message: Message

    var body: some View {
        HStack(alignment: .bottom, spacing: 0) {
            if message.isUser { Spacer(minLength: 60) }

            switch message.roleEnum {
            case .user:
                userBubble
            case .assistant:
                assistantBubble
            case .tool:
                toolBubble
            case .system:
                EmptyView()
            }

            if !message.isUser { Spacer(minLength: 60) }
        }
    }

    // MARK: - User bubble

    private var userBubble: some View {
        Text(message.content)
            .font(JarvisTheme.bubbleFont)
            .foregroundStyle(.white)
            .padding(.horizontal, JarvisTheme.bubblePadding)
            .padding(.vertical, 10)
            .background(JarvisTheme.userBubble)
            .clipShape(
                .rect(
                    topLeadingRadius: JarvisTheme.cornerRadius,
                    bottomLeadingRadius: JarvisTheme.cornerRadius,
                    bottomTrailingRadius: 4,
                    topTrailingRadius: JarvisTheme.cornerRadius
                )
            )
    }

    // MARK: - Assistant bubble

    private var assistantBubble: some View {
        Text(message.content)
            .font(JarvisTheme.bubbleFont)
            .foregroundStyle(.white)
            .padding(.horizontal, JarvisTheme.bubblePadding)
            .padding(.vertical, 10)
            .background(JarvisTheme.assistantBubble)
            .clipShape(
                .rect(
                    topLeadingRadius: 4,
                    bottomLeadingRadius: JarvisTheme.cornerRadius,
                    bottomTrailingRadius: JarvisTheme.cornerRadius,
                    topTrailingRadius: JarvisTheme.cornerRadius
                )
            )
    }

    // MARK: - Tool result bubble

    private var toolBubble: some View {
        HStack(spacing: 6) {
            if let toolName = message.toolName,
               let tool = JarvisToolName(rawValue: toolName) {
                Image(systemName: tool.sfSymbol)
                    .font(.caption2)
                    .foregroundStyle(JarvisTheme.accent)
            } else {
                Image(systemName: "function")
                    .font(.caption2)
                    .foregroundStyle(JarvisTheme.accent)
            }

            Text(message.content)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(3)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(JarvisTheme.toolBubble)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(JarvisTheme.accent.opacity(0.3), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
