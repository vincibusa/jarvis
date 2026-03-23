import Foundation

@Observable
@MainActor
final class AudioPickerCoordinator {

    var isPicking: Bool = false
    private var continuation: CheckedContinuation<URL?, Never>?

    /// Suspends until the user picks a file (or cancels).
    func requestAudioFile() async -> URL? {
        isPicking = true
        return await withCheckedContinuation { cont in
            self.continuation = cont
        }
    }

    /// Call this from the UI layer when a file URL has been selected.
    func deliverFile(_ url: URL?) {
        continuation?.resume(returning: url)
        continuation = nil
        isPicking = false
    }

    /// Convenience: cancel the pending request.
    func cancel() {
        deliverFile(nil)
    }
}
