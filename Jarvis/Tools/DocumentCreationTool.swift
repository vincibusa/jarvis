import Foundation

/// Tool that generates PDF, DOCX, or XLSX files on-device and presents a share sheet.
@MainActor
final class DocumentCreationTool {

    private let coordinator: DocumentShareCoordinator

    init(coordinator: DocumentShareCoordinator) {
        self.coordinator = coordinator
    }

    // MARK: - PDF

    func createPDF(title: String, content: String, filename: String?) async -> String {
        do {
            let url = try DocumentCreationService.createPDF(
                title: title,
                content: content,
                filename: filename
            )
            let shared = await coordinator.shareDocument(url: url)
            return shared
                ? "PDF '\(title)' creato e condiviso."
                : "PDF '\(title)' creato. Puoi condividerlo in seguito."
        } catch {
            return "Errore nella creazione del PDF: \(error.localizedDescription)"
        }
    }

    // MARK: - DOCX

    func createDocx(title: String, content: String, filename: String?) async -> String {
        do {
            let url = try DocumentCreationService.createDocx(
                title: title,
                content: content,
                filename: filename
            )
            let shared = await coordinator.shareDocument(url: url)
            return shared
                ? "Documento Word '\(title)' creato e condiviso."
                : "Documento Word '\(title)' creato. Puoi condividerlo in seguito."
        } catch {
            return "Errore nella creazione del documento Word: \(error.localizedDescription)"
        }
    }

    // MARK: - XLSX

    func createXlsx(
        sheetName: String,
        headers: String,
        rows: String,
        filename: String?
    ) async -> String {
        do {
            let url = try DocumentCreationService.createXlsx(
                sheetName: sheetName,
                headers: headers,
                rows: rows,
                filename: filename
            )
            let shared = await coordinator.shareDocument(url: url)
            return shared
                ? "Foglio Excel '\(sheetName)' creato e condiviso."
                : "Foglio Excel '\(sheetName)' creato. Puoi condividerlo in seguito."
        } catch {
            return "Errore nella creazione del foglio Excel: \(error.localizedDescription)"
        }
    }
}
