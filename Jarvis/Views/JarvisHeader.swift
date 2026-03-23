import SwiftUI

struct JarvisHeader: View {
    let state: LLMService.State
    let onSettings: () -> Void

    private var statusColor: Color {
        switch state.statusDot {
        case .green:  return JarvisTheme.statusGreen
        case .orange: return JarvisTheme.statusOrange
        case .gray:   return .gray
        }
    }

    private var statusLabel: String {
        switch state {
        case .idle:                   return "In attesa"
        case .downloading(let p):     return "Download \(Int(p * 100))%"
        case .loading:                return "Caricamento..."
        case .ready:                  return "Online"
        case .generating:             return "Elaborazione..."
        case .error:                  return "Errore"
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            // Status dot with pulse when generating
            ZStack {
                if case .generating = state {
                    Circle()
                        .fill(statusColor.opacity(0.3))
                        .frame(width: 16, height: 16)
                        .scaleEffect(1.4)
                        .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: true)
                }
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
            }

            // Title
            Text("JARVIS")
                .font(JarvisTheme.headerFont)
                .foregroundStyle(.white)

            // Status
            Text(statusLabel)
                .font(JarvisTheme.monoSmall)
                .foregroundStyle(.gray)

            Spacer()

            // Settings button
            Button(action: onSettings) {
                Image(systemName: "gearshape")
                    .font(.body)
                    .foregroundStyle(.gray)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            Rectangle()
                .fill(.black.opacity(0.8))
                .ignoresSafeArea(edges: .top)
        )
    }
}
