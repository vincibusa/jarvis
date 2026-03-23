import SwiftUI

struct ThinkingIndicator: View {
    @State private var animating = false

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(Color.gray.opacity(0.6))
                    .frame(width: 8, height: 8)
                    .scaleEffect(animating ? 1.3 : 0.7)
                    .animation(
                        .easeInOut(duration: 0.5)
                            .repeatForever(autoreverses: true)
                            .delay(Double(i) * 0.15),
                        value: animating
                    )
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(JarvisTheme.assistantBubble, in: .rect(cornerRadius: JarvisTheme.cornerRadius))
        .onAppear { animating = true }
        .onDisappear { animating = false }
    }
}

#Preview {
    ThinkingIndicator()
        .padding()
        .background(Color.black)
}
