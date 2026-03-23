import AppIntents

struct QuestionEntity: AppEntity {
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Domanda")
    static var defaultQuery = QuestionQuery()

    var id: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(id)")
    }
}

struct QuestionQuery: EntityStringQuery {
    func entities(for identifiers: [String]) async throws -> [QuestionEntity] {
        identifiers.map { QuestionEntity(id: $0) }
    }

    func entities(matching string: String) async throws -> [QuestionEntity] {
        [QuestionEntity(id: string)]
    }

    func suggestedEntities() async throws -> [QuestionEntity] {
        []
    }
}
