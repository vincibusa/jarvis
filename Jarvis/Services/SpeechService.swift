import Foundation
import AVFoundation
import Speech
import Observation

@Observable
@MainActor
final class SpeechService: NSObject {

    enum ListeningState {
        case idle
        case listening
        case processing
    }

    var listeningState: ListeningState = .idle
    var partialTranscription: String = ""
    var isSpeaking: Bool = false
    var isAuthorized: Bool = false

    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "it-IT"))
    private let synthesizer = AVSpeechSynthesizer()
    private var audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var speakingContinuation: CheckedContinuation<Void, Never>?

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    // MARK: - Authorization

    func requestAuthorization() async -> Bool {
        let speechStatus = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }

        let micStatus = await AVAudioApplication.requestRecordPermission()

        isAuthorized = (speechStatus == .authorized) && micStatus
        return isAuthorized
    }

    // MARK: - STT

    func startListening() {
        guard listeningState == .idle else { return }
        listeningState = .listening
        partialTranscription = ""

        configureAudioSession(forRecording: true)

        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let request = recognitionRequest else { return }
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = true

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }

        audioEngine.prepare()
        try? audioEngine.start()

        recognitionTask = speechRecognizer?.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            if let result {
                Task { @MainActor in
                    self.partialTranscription = result.bestTranscription.formattedString
                }
            }
            if error != nil || result?.isFinal == true {
                Task { @MainActor in
                    self.stopAudioEngine()
                }
            }
        }
    }

    func stopListening() -> String {
        listeningState = .processing
        stopAudioEngine()
        let result = partialTranscription
        partialTranscription = ""
        listeningState = .idle
        return result
    }

    private func stopAudioEngine() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        recognitionTask?.cancel()
        recognitionTask = nil
    }

    // MARK: - TTS

    func speak(_ text: String) async {
        guard !text.isEmpty else { return }

        // Stop any ongoing recognition
        if listeningState != .idle { _ = stopListening() }
        configureAudioSession(forRecording: false)

        // Strip markdown and formatting artifacts
        let cleanText = stripForSpeech(text)

        isSpeaking = true

        await withCheckedContinuation { [weak self] (continuation: CheckedContinuation<Void, Never>) in
            guard let self else { continuation.resume(); return }
            self.speakingContinuation = continuation

            let utterance = AVSpeechUtterance(string: cleanText)
            utterance.voice = AVSpeechSynthesisVoice(language: "it-IT")
            utterance.rate = 0.52
            utterance.pitchMultiplier = 1.0
            utterance.volume = 1.0
            self.synthesizer.speak(utterance)
        }

        isSpeaking = false
    }

    func stopSpeaking() {
        synthesizer.stopSpeaking(at: .immediate)
    }

    // MARK: - Helpers

    private func configureAudioSession(forRecording: Bool) {
        let session = AVAudioSession.sharedInstance()
        do {
            if forRecording {
                try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
            } else {
                try session.setCategory(.playback, mode: .default)
            }
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            print("Audio session error: \(error)")
        }
    }

    private func stripForSpeech(_ text: String) -> String {
        var result = text
        // Remove think blocks
        while let start = result.range(of: "<think>"),
              let end = result.range(of: "</think>") {
            result.removeSubrange(start.lowerBound...end.upperBound)
        }
        // Trim whitespace
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - AVSpeechSynthesizerDelegate

extension SpeechService: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.speakingContinuation?.resume()
            self.speakingContinuation = nil
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.speakingContinuation?.resume()
            self.speakingContinuation = nil
        }
    }
}
