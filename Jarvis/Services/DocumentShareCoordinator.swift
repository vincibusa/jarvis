import Foundation

/// Bridges async tool execution to the SwiftUI share sheet.
/// Mirrors the pattern used by EmailComposerCoordinator.
@Observable
@MainActor
final class DocumentShareCoordinator {

    /// Set by the tool when a document is ready to share. ChatView observes this.
    var pendingShareURL: URL? = nil
    var hasPendingShare: Bool { pendingShareURL != nil }

    private var continuation: CheckedContinuation<Bool, Never>?

    /// Called by DocumentCreationTool. Suspends until the user dismisses the share sheet.
    func shareDocument(url: URL) async -> Bool {
        pendingShareURL = url
        return await withCheckedContinuation { cont in
            self.continuation = cont
        }
    }

    /// Called by ChatView when the share sheet is dismissed (with or without sharing).
    func deliverResult(shared: Bool) {
        continuation?.resume(returning: shared)
        continuation = nil
        pendingShareURL = nil
    }
}
