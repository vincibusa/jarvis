import Foundation
import MessageUI

@MainActor
final class EmailTool {
    private let coordinator: EmailComposerCoordinator

    init(coordinator: EmailComposerCoordinator) {
        self.coordinator = coordinator
    }

    func sendEmail(to: String, subject: String, body: String) async -> String {
        guard MFMailComposeViewController.canSendMail() else {
            return "Errore: nessun account email configurato su questo dispositivo."
        }

        let sent = await coordinator.composeEmail(to: to, subject: subject, body: body)
        return sent ? "Email inviata con successo a \(to)." : "Invio email annullato."
    }
}
