import Foundation
import Vision
import UIKit

final class VisionService {

    // MARK: - OCR

    func recognizeText(in image: CGImage) async throws -> String {
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
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
    }

    // MARK: - Classification

    func classifyImage(_ image: CGImage) async throws -> String {
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
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
    }

    // MARK: - Barcode detection

    func detectBarcodes(in image: CGImage) async throws -> [String] {
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let request = VNDetectBarcodesRequest { request, error in
                    if let error = error {
                        continuation.resume(throwing: error)
                        return
                    }
                    let observations = request.results as? [VNBarcodeObservation] ?? []
                    let payloads = observations.compactMap { $0.payloadStringValue }
                    continuation.resume(returning: payloads)
                }

                let handler = VNImageRequestHandler(cgImage: image, options: [:])
                do {
                    try handler.perform([request])
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    // MARK: - Combined analysis

    func analyzeImage(_ cgImage: CGImage) async -> String {
        let ocrText = try? await recognizeText(in: cgImage)
        let labels = try? await classifyImage(cgImage)
        let barcodes = try? await detectBarcodes(in: cgImage)

        let hasOCR      = !(ocrText?.isEmpty ?? true)
        let hasLabels   = !(labels?.isEmpty ?? true)
        let hasBarcodes = !(barcodes?.isEmpty ?? true)

        guard hasOCR || hasLabels || hasBarcodes else {
            return "Nessun contenuto rilevato."
        }

        var parts: [String] = []
        if hasOCR      { parts.append("Testo trovato: \(ocrText!)") }
        if hasLabels   { parts.append("Classificazione: \(labels!)") }
        if hasBarcodes { parts.append("Codici rilevati: \(barcodes!.joined(separator: ", "))") }
        return parts.joined(separator: "\n")
    }

    // MARK: - Document (multi-page) analysis

    func analyzeDocument(images: [CGImage]) async -> String {
        guard !images.isEmpty else {
            return "Nessuna pagina scansionata."
        }

        var pageResults: [String] = []
        for (index, page) in images.enumerated() {
            let text = (try? await recognizeText(in: page)) ?? ""
            if !text.isEmpty {
                pageResults.append("--- Pagina \(index + 1) ---\n\(text)")
            }
        }

        guard !pageResults.isEmpty else {
            return "Nessun testo rilevato nel documento."
        }

        return pageResults.joined(separator: "\n\n")
    }
}
