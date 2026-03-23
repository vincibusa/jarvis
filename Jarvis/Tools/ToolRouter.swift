import Foundation

@MainActor
final class ToolRouter: @unchecked Sendable {

    // MARK: - Dependencies

    let memoryService: MemoryService

    private let calendarTool  = CalendarTool()
    private let reminderTool  = ReminderTool()
    private let locationTool  = LocationTool()
    private let visionService = VisionService()
    private lazy var imageTool   = ImageTool(visionService: visionService)
    private lazy var memoryTool: MemoryTool = { MemoryTool(memoryService: memoryService) }()

    // MARK: - Init

    init(memoryService: MemoryService) {
        self.memoryService = memoryService
    }

    // MARK: - Dispatch

    func execute(name: String, arguments: [String: Any]) async throws -> String {
        guard let toolName = JarvisToolName(rawValue: name) else {
            throw ToolError.unknownTool(name)
        }

        switch toolName {

        case .getCurrentDatetime:
            return TimeTool.getCurrentDatetime()

        case .getEvents:
            let days = arguments["days"] as? Int ?? 7
            return try await calendarTool.getEvents(days: days)

        case .createEvent:
            guard let title = arguments["title"] as? String,
                  let startDate = arguments["start_date"] as? String else {
                throw ToolError.missingArgument("title / start_date")
            }
            let endDate = arguments["end_date"] as? String
            let notes   = arguments["notes"] as? String
            return try await calendarTool.createEvent(
                title: title,
                startDate: startDate,
                endDate: endDate,
                notes: notes
            )

        case .getReminders:
            return try await reminderTool.getReminders()

        case .createReminder:
            guard let title = arguments["title"] as? String else {
                throw ToolError.missingArgument("title")
            }
            let dueDate = arguments["due_date"] as? String
            let notes   = arguments["notes"] as? String
            return try await reminderTool.createReminder(
                title: title,
                dueDate: dueDate,
                notes: notes
            )

        case .getCurrentLocation:
            return try await locationTool.getCurrentLocation()

        case .analyzeImage:
            guard let source = arguments["source"] as? String else {
                throw ToolError.missingArgument("source")
            }
            let question = arguments["question"] as? String
            return try await imageTool.analyzeImage(source: source, question: question)

        case .remember:
            guard let key     = arguments["key"] as? String,
                  let content = arguments["content"] as? String else {
                throw ToolError.missingArgument("key / content")
            }
            return memoryTool.remember(key: key, content: content)

        case .recall:
            guard let query = arguments["query"] as? String else {
                throw ToolError.missingArgument("query")
            }
            return memoryTool.recall(query: query)
        }
    }

    // MARK: - Errors

    enum ToolError: LocalizedError {
        case unknownTool(String)
        case missingArgument(String)

        var errorDescription: String? {
            switch self {
            case .unknownTool(let name):
                return "Tool sconosciuto: '\(name)'."
            case .missingArgument(let param):
                return "Parametro obbligatorio mancante: \(param)."
            }
        }
    }
}
