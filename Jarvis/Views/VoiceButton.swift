import SwiftUI

struct VoiceButton: View {
    @Binding var isListening: Bool
    var onStart: () -> Void
    var onStop: () -> Void

    @State private var pulseScale: CGFloat = 1.0

    var body: some View {
        ZStack {
            // Pulsing rings (visible when listening)
            if isListening {
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .stroke(JarvisTheme.accent.opacity(0.25 - Double(i) * 0.07), lineWidth: 2)
                        .frame(width: 60 + CGFloat(i) * 20, height: 60 + CGFloat(i) * 20)
                        .scaleEffect(pulseScale)
                        .animation(
                            .easeOut(duration: 1.2)
                                .repeatForever(autoreverses: false)
                                .delay(Double(i) * 0.3),
                            value: pulseScale
                        )
                }
            }

            // Main button
            Circle()
                .fill(isListening ? JarvisTheme.accent : JarvisTheme.inputBackground)
                .frame(width: 52, height: 52)
                .overlay {
                    Image(systemName: isListening ? "stop.fill" : "mic.fill")
                        .font(.title3)
                        .foregroundStyle(isListening ? .white : .gray)
                }
                .scaleEffect(isListening ? 1.05 : 1.0)
                .animation(.spring(response: 0.3), value: isListening)
        }
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    if !isListening {
                        isListening = true
                        pulseScale = 1.5
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        onStart()
                    }
                }
                .onEnded { _ in
                    if isListening {
                        isListening = false
                        pulseScale = 1.0
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        onStop()
                    }
                }
        )
        .onAppear {
            if isListening { pulseScale = 1.5 }
        }
    }
}
