import SwiftUI

struct ModelDownloadView: View {
    @Environment(LLMService.self) private var llm
    @State private var showError = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 40) {
                // Logo / title
                VStack(spacing: 12) {
                    Text("J.A.R.V.I.S")
                        .font(.system(size: 42, weight: .bold, design: .monospaced))
                        .foregroundStyle(JarvisTheme.accent)

                    Text("Just A Rather Very Intelligent System")
                        .font(.caption)
                        .foregroundStyle(.gray)
                        .multilineTextAlignment(.center)
                }

                // Status area
                VStack(spacing: 20) {
                    stateView

                    // Model info
                    HStack(spacing: 4) {
                        Image(systemName: "cpu")
                            .font(.caption)
                            .foregroundStyle(.gray)
                        Text("Qwen3.5-2B · 4-bit · ~1.4 GB")
                            .font(JarvisTheme.monoSmall)
                            .foregroundStyle(.gray)
                    }

                    HStack(spacing: 4) {
                        Image(systemName: "lock.shield")
                            .font(.caption)
                            .foregroundStyle(JarvisTheme.statusGreen)
                        Text("100% on-device · Nessun cloud")
                            .font(.caption)
                            .foregroundStyle(JarvisTheme.statusGreen)
                    }
                }

                Spacer()

                // Privacy note
                Text("Il modello viene scaricato una sola volta e salvato localmente.\nNessun dato personale lascia il dispositivo.")
                    .font(.caption2)
                    .foregroundStyle(.gray.opacity(0.6))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
            .padding(.top, 100)
            .padding(.bottom, 40)
        }
        .alert("Errore", isPresented: $showError) {
            Button("Riprova") { Task { await llm.loadModel() } }
            Button("Annulla", role: .cancel) {}
        } message: {
            if case .error(let msg) = llm.state {
                Text(msg)
            }
        }
        .onChange(of: llm.state) { _, newState in
            if case .error = newState { showError = true }
        }
    }

    @ViewBuilder
    private var stateView: some View {
        switch llm.state {
        case .idle:
            Button {
                Task { await llm.loadModel() }
            } label: {
                HStack {
                    Image(systemName: "bolt.fill")
                    Text("Inizializza Jarvis")
                        .font(.system(.body, design: .monospaced).bold())
                }
                .foregroundStyle(.black)
                .padding(.horizontal, 32)
                .padding(.vertical, 14)
                .background(JarvisTheme.accent)
                .clipShape(Capsule())
            }

        case .downloading(let progress):
            VStack(spacing: 12) {
                ProgressView(value: progress)
                    .progressViewStyle(LinearProgressViewStyle(tint: JarvisTheme.accent))
                    .frame(width: 260)

                Text("Download \(Int(progress * 100))%")
                    .font(JarvisTheme.monoSmall)
                    .foregroundStyle(.gray)

                Text("Connessione Wi-Fi consigliata")
                    .font(.caption2)
                    .foregroundStyle(.gray.opacity(0.5))
            }

        case .loading:
            VStack(spacing: 12) {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: JarvisTheme.accent))
                    .scaleEffect(1.2)

                Text("Caricamento modello...")
                    .font(JarvisTheme.monoSmall)
                    .foregroundStyle(.gray)
            }

        case .error:
            VStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.title2)
                    .foregroundStyle(.red)
                Text("Errore nel caricamento")
                    .foregroundStyle(.red)
                    .font(.callout)
                Button("Riprova") {
                    Task { await llm.loadModel() }
                }
                .foregroundStyle(JarvisTheme.accent)
            }

        case .ready, .generating:
            EmptyView()
        }
    }
}
