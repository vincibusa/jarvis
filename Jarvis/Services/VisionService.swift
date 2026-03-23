import Foundation
import Vision
import UIKit

final class VisionService {

    func recognizeText(in image: CGImage) async throws -> String {
        return try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                let observations = request.results as? [VNRecognizedTextObservation] ?? []
                let text = observations
                    .compactMap { $0.topCandidates(1).first?.string }
                    .joined(separator: "\n")
                continuation.resume(returning: text)
            }
            request.recognitionLevel = .accurate
            request.recognitionLanguages = ["it-IT", "en-US"]

            let handler = VNImageRequestHandler(cgImage: image, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    func classifyImage(_ image: CGImage) async throws -> String {
        return try await withCheckedThrowingContinuation { continuation in
            let request = VNClassifyImageRequest { request, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                let observations = request.results as? [VNClassificationObservation] ?? []
                let top3 = observations
                    .filter { $0.confidence > 0.1 }
                    .prefix(3)
                    .map { "\($0.identifier) (\(Int($0.confidence * 100))%)" }
                    .joined(separator: ", ")
                continuation.resume(returning: top3)
            }

            let handler = VNImageRequestHandler(cgImage: image, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    func analyzeImage(_ cgImage: CGImage) async -> String {
        let ocrText = try? await recognizeText(in: cgImage)
        let labels = try? await classifyImage(cgImage)

        let hasOCR = !(ocrText?.isEmpty ?? true)
        let hasLabels = !(labels?.isEmpty ?? true)

        guard hasOCR || hasLabels else {
            return "Nessun contenuto rilevato."
        }

        var parts: [String] = []
        if hasOCR {
            parts.append("Testo trovato: \(ocrText!)")
        }
        if hasLabels {
            parts.append("Classificazione: \(labels!)")
        }
        return parts.joined(separator: "\n")
    }
}
