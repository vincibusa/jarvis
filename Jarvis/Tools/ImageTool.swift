import Foundation

final class ImageTool {

    private let visionService: VisionService

    init(visionService: VisionService) {
        self.visionService = visionService
    }

    // MARK: - Analyze image

    func analyzeImage(source: String, question: String? = nil) async throws -> String {
        // Camera and photo-picker require UI coordination (UIImagePickerController /
        // PHPickerViewController) which must be driven from the view layer.
        // ToolRouter will wire the real implementation once the UI picker is available.
        return "Funzionalità immagine disponibile. L'utente dovrà selezionare un'immagine dall'interfaccia."
    }
}
