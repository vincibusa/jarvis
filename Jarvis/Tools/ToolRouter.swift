import Foundation

@MainActor
final class ToolRouter: @unchecked Sendable {

    // MARK: - Dependencies

    let memoryService: MemoryService
    let imagePickerCoordinator: ImagePickerCoordinator
    let emailComposerCoordinator: EmailComposerCoordinator
    let audioPickerCoordinator: AudioPickerCoordinator

    private let calendarTool  = CalendarTool()
    private let reminderTool  = ReminderTool()
    private let locationTool  = LocationTool()
    private let visionService = VisionService()
    private lazy var imageTool: ImageTool = {
        ImageTool(visionService: visionService, coordinator: imagePickerCoordinator)
    }()
    private let memoryTool: MemoryTool
    private let webSearchTool = WebSearchTool()
    private lazy var emailTool: EmailTool = { EmailTool(coordinator: emailComposerCoordinator) }()
    private lazy var audioTool: AudioTool = { AudioTool(coordinator: audioPickerCoordinator) }()

    // Document tool — configured after DocumentService is available
    var documentTool: DocumentTool?

    // MARK: - Init

    init(
        memoryService: MemoryService,
        embeddingService: EmbeddingService,
        memoryVectorStore: VectorStore,
        imagePickerCoordinator: ImagePickerCoordinator,
        emailComposerCoordinator: EmailComposerCoordinator,
        audioPickerCoordinator: AudioPickerCoordinator
    ) {
        self.memoryService = memoryService
        self.imagePickerCoordinator = imagePickerCoordinator
        self.emailComposerCoordinator = emailComposerCoordinator
        self.audioPickerCoordinator = audioPickerCoordinator
        self.memoryTool = MemoryTool(
            memoryService: memoryService,
            embeddingService: embeddingService,
            vectorStore: memoryVectorStore
        )
    }

    var memoryToolRef: MemoryTool { memoryTool }

    // MARK: - Document configuration

    func configureDocuments(documentTool: DocumentTool) {
        self.documentTool = documentTool
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

        case .scanDocument:
            return try await imageTool.scanDocument()

        case .remember:
            guard let key     = arguments["key"] as? String,
                  let content = arguments["content"] as? String else {
                throw ToolError.missingArgument("key / content")
            }
            return await memoryTool.remember(key: key, content: content)

        case .recall:
            guard let query = arguments["query"] as? String else {
                throw ToolError.missingArgument("query")
            }
            return await memoryTool.recall(query: query)

        case .webSearch:
            guard let query = arguments["query"] as? String else {
                throw ToolError.missingArgument("query")
            }
            return await webSearchTool.webSearch(query: query)

        case .sendEmail:
            guard let to      = arguments["to"] as? String,
                  let subject = arguments["subject"] as? String,
                  let body    = arguments["body"] as? String else {
                throw ToolError.missingArgument("to / subject / body")
            }
            return await emailTool.sendEmail(to: to, subject: subject, body: body)

        case .transcribeAudio:
            return await audioTool.transcribeAudio()

        case .summarizeAudio:
            return await audioTool.summarizeAudio()

        case .searchDocuments:
            guard let query = arguments["query"] as? String else {
                throw ToolError.missingArgument("query")
            }
            // top_k can arrive as Int or as String (model quirk)
            let topK: Int
            if let i = arguments["top_k"] as? Int {
                topK = i
            } else if let s = arguments["top_k"] as? String, let i = Int(s) {
                topK = i
            } else {
                topK = 3
            }
            guard let tool = documentTool else {
                return "Il sistema documenti non è ancora configurato."
            }
            return try await tool.searchDocuments(query: query, topK: topK)

        case .listDocuments:
            guard let tool = documentTool else {
                return "Il sistema documenti non è ancora configurato."
            }
            return tool.listDocuments()
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
