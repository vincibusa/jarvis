import Foundation
import UIKit

@Observable
@MainActor
final class ImagePickerCoordinator {

    enum PickerSource: Equatable {
        case camera
        case photoLibrary
        case documentScanner
    }

    var pendingRequest: PickerSource? = nil
    var pendingQuestion: String? = nil
    private var continuation: CheckedContinuation<CGImage?, Never>?

    func requestImage(source: PickerSource, question: String? = nil) async -> CGImage? {
        pendingQuestion = question
        pendingRequest = source
        return await withCheckedContinuation { cont in
            self.continuation = cont
        }
    }

    func deliverImage(_ image: CGImage?) {
        continuation?.resume(returning: image)
        continuation = nil
        pendingRequest = nil
        pendingQuestion = nil
    }

    func cancel() {
        deliverImage(nil)
    }
}
