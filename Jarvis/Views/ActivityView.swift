import SwiftUI
import UIKit

/// Wraps UIActivityViewController for use inside a SwiftUI sheet.
struct ActivityView: UIViewControllerRepresentable {

    let url: URL
    var onComplete: (Bool) -> Void

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(
            activityItems: [url],
            applicationActivities: nil
        )
        controller.completionWithItemsHandler = { _, completed, _, _ in
            onComplete(completed)
        }
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
