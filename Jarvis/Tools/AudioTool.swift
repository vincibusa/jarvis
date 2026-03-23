import Foundation

@MainActor
final class AudioTool {

    private let transcriptionService = AudioTranscriptionService()
    private let coordinator: AudioPickerCoordinator

    init(coordinator: AudioPickerCoordinator) {
        self.coordinator = coordinator
    }

    // MARK: - Public API

    /// Prompts the user to pick an audio file, then transcribes it on-device.
    func transcribeAudio() async -> String {
        guard let fileURL = await coordinator.requestAudioFile() else {
            return "Nessun file audio selezionato."
        }

        // Start accessing the security-scoped resource granted by the document picker.
        guard fileURL.startAccessingSecurityScopedResource() else {
            return "Errore: impossibile accedere al file."
        }
        defer { fileURL.stopAccessingSecurityScopedResource() }

        do {
            let transcript = try await transcriptionService.transcribe(fileURL: fileURL)
            if transcript.isEmpty {
                return "Nessun testo riconosciuto nel file audio."
            }
            return "Trascrizione:\n\(transcript)"
        } catch {
            return "Errore nella trascrizione: \(error.localizedDescription)"
        }
    }

    /// Transcribes the audio and appends a summarisation hint for the LLM.
    func summarizeAudio() async -> String {
        let transcript = await transcribeAudio()
        // If transcription failed or returned nothing, propagate the message unchanged.
        if transcript.starts(with: "Errore") || transcript.starts(with: "Nessun") {
            return transcript
        }
        return "\(transcript)\n\n[L'utente chiede un riassunto di questo audio. Fornisci un riassunto conciso.]"
    }
}
