import Foundation
import UIKit

@MainActor
final class ImageTool {

    private let visionService: VisionService
    private let coordinator: ImagePickerCoordinator

    init(visionService: VisionService, coordinator: ImagePickerCoordinator) {
        self.visionService = visionService
        self.coordinator = coordinator
    }

    // MARK: - Analyze image

    func analyzeImage(source: String, question: String? = nil) async throws -> String {
        let pickerSource: ImagePickerCoordinator.PickerSource =
            source == "camera" ? .camera : .photoLibrary
        guard let cgImage = await coordinator.requestImage(source: pickerSource, question: question) else {
            return "Nessuna immagine selezionata."
        }
        return await visionService.analyzeImage(cgImage)
    }

    // MARK: - Scan document

    func scanDocument() async throws -> String {
        guard let cgImage = await coordinator.requestImage(source: .documentScanner) else {
            return "Scansione annullata."
        }
        return await visionService.analyzeImage(cgImage)
    }
}
