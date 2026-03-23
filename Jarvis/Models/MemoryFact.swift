import SwiftData
import Foundation

@Model
final class MemoryFact {
    var id: UUID
    var key: String
    var content: String
    var createdAt: Date

    init(key: String, content: String) {
        self.id = UUID()
        self.key = key
        self.content = content
        self.createdAt = Date()
    }
}
