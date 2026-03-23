import SwiftUI
import PhotosUI

struct ImagePickerView: UIViewControllerRepresentable {
    let source: ImagePickerCoordinator.PickerSource
    let onImagePicked: (CGImage?) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onImagePicked: onImagePicked)
    }

    func makeUIViewController(context: Context) -> UIViewController {
        switch source {
        case .camera:
            let picker = UIImagePickerController()
            picker.sourceType = .camera
            picker.delegate = context.coordinator
            return picker
        case .photoLibrary:
            var config = PHPickerConfiguration()
            config.selectionLimit = 1
            config.filter = .images
            let picker = PHPickerViewController(configuration: config)
            picker.delegate = context.coordinator
            return picker
        case .documentScanner:
            // documentScanner is handled by DocumentScannerView; return empty controller as fallback
            return UIViewController()
        }
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}

    // MARK: - Coordinator

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate, PHPickerViewControllerDelegate {
        private let onImagePicked: (CGImage?) -> Void

        init(onImagePicked: @escaping (CGImage?) -> Void) {
            self.onImagePicked = onImagePicked
        }

        // UIImagePickerControllerDelegate
        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            picker.dismiss(animated: true)
            let uiImage = info[.editedImage] as? UIImage ?? info[.originalImage] as? UIImage
            onImagePicked(uiImage?.cgImage)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true)
            onImagePicked(nil)
        }

        // PHPickerViewControllerDelegate
        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)
            guard let result = results.first else {
                onImagePicked(nil)
                return
            }
            result.itemProvider.loadObject(ofClass: UIImage.self) { [weak self] object, _ in
                let cgImage = (object as? UIImage)?.cgImage
                DispatchQueue.main.async {
                    self?.onImagePicked(cgImage)
                }
            }
        }
    }
}
