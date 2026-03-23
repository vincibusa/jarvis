import Foundation
import Speech

actor AudioTranscriptionService {

    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "it-IT"))

    /// Transcribe an audio file on-device using SFSpeechRecognizer.
    func transcribe(fileURL: URL) async throws -> String {
        guard SFSpeechRecognizer.authorizationStatus() == .authorized else {
            throw AudioTranscriptionError.notAuthorized
        }

        guard let recognizer = speechRecognizer, recognizer.isAvailable else {
            throw AudioTranscriptionError.recognizerUnavailable
        }

        let request = SFSpeechURLRecognitionRequest(url: fileURL)
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = false

        return try await withCheckedThrowingContinuation { continuation in
            // Use a flag to ensure the continuation is only resumed once.
            // SFSpeechRecognizer callbacks may fire multiple times.
            var resumed = false

            recognizer.recognitionTask(with: request) { result, error in
                guard !resumed else { return }

                if let error = error {
                    resumed = true
                    continuation.resume(throwing: error)
                    return
                }

                if let result = result, result.isFinal {
                    resumed = true
                    continuation.resume(returning: result.bestTranscription.formattedString)
                    return
                }

                // Terminal case: nil result and nil error means silent or unrecognisable audio.
                if result == nil {
                    resumed = true
                    continuation.resume(returning: "")
                }
            }
        }
    }

    // MARK: - Errors

    enum AudioTranscriptionError: LocalizedError {
        case notAuthorized
        case recognizerUnavailable
        case transcriptionFailed(String)

        var errorDescription: String? {
            switch self {
            case .notAuthorized:
                return "Permesso di riconoscimento vocale non concesso."
            case .recognizerUnavailable:
                return "Riconoscimento vocale non disponibile."
            case .transcriptionFailed(let msg):
                return "Trascrizione fallita: \(msg)"
            }
        }
    }
}
