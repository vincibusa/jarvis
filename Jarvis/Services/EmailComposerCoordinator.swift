import Foundation
import UIKit
import MessageUI

@Observable
@MainActor
final class EmailComposerCoordinator {
    struct EmailRequest {
        let to: String
        let subject: String
        let body: String
    }

    var pendingEmail: EmailRequest? = nil
    var hasPendingEmail: Bool { pendingEmail != nil }
    private var continuation: CheckedContinuation<Bool, Never>?

    func composeEmail(to: String, subject: String, body: String) async -> Bool {
        guard MFMailComposeViewController.canSendMail() else {
            return false
        }
        pendingEmail = EmailRequest(to: to, subject: subject, body: body)
        return await withCheckedContinuation { cont in
            self.continuation = cont
        }
    }

    func deliverResult(sent: Bool) {
        continuation?.resume(returning: sent)
        continuation = nil
        pendingEmail = nil
    }
}
