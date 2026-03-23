import SwiftUI

// MARK: - Custom environment key for optional DocumentService

private struct DocumentServiceKey: EnvironmentKey {
    static let defaultValue: DocumentService? = nil
}

extension EnvironmentValues {
    var documentService: DocumentService? {
        get { self[DocumentServiceKey.self] }
        set { self[DocumentServiceKey.self] = newValue }
    }
}
