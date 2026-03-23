import Foundation
import SwiftData

@Model
final class Document {
    var id: UUID
    var name: String
    var fileType: String
    var importedAt: Date
    var chunkCount: Int
    var fileSize: Int64

    init(name: String, fileType: String, chunkCount: Int = 0, fileSize: Int64 = 0) {
        self.id = UUID()
        self.name = name
        self.fileType = fileType
        self.importedAt = Date()
        self.chunkCount = chunkCount
        self.fileSize = fileSize
    }
}
