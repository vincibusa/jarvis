import Foundation
import MLXLMCommon
import Tokenizers

// MARK: - Tool names

enum JarvisToolName: String, CaseIterable {
    case getCurrentDatetime  = "get_current_datetime"
    case getEvents           = "get_events"
    case createEvent         = "create_event"
    case createReminder      = "create_reminder"
    case getReminders        = "get_reminders"
    case getCurrentLocation  = "get_current_location"
    case analyzeImage        = "analyze_image"
    case remember            = "remember"
    case recall              = "recall"

    var displayName: String {
        switch self {
        case .getCurrentDatetime: return "Orologio"
        case .getEvents:          return "Calendario"
        case .createEvent:        return "Nuovo evento"
        case .createReminder:     return "Promemoria"
        case .getReminders:       return "Promemoria"
        case .getCurrentLocation: return "Posizione"
        case .analyzeImage:       return "Analisi immagine"
        case .remember:           return "Memoria"
        case .recall:             return "Ricordo"
        }
    }

    var sfSymbol: String {
        switch self {
        case .getCurrentDatetime: return "clock"
        case .getEvents:          return "calendar"
        case .createEvent:        return "calendar.badge.plus"
        case .createReminder:     return "bell.badge"
        case .getReminders:       return "bell"
        case .getCurrentLocation: return "location"
        case .analyzeImage:       return "eye"
        case .remember:           return "brain.head.profile"
        case .recall:             return "brain"
        }
    }
}

// MARK: - ToolSpec registry
// ToolSpec is [String: any Sendable] from Tokenizers (re-exported by MLXLMCommon)
// Format: {"type": "function", "function": {"name": ..., "description": ..., "parameters": ...}}

enum ToolDefinitions {

    static var allToolSpecs: [ToolSpec] {
        [
            timeToolSpec,
            getEventsSpec,
            createEventSpec,
            createReminderSpec,
            getRemindersSpec,
            getCurrentLocationSpec,
            analyzeImageSpec,
            rememberSpec,
            recallSpec,
        ]
    }

    // MARK: - Helpers

    private static func makeTool(
        name: String,
        description: String,
        parameters: [ToolParameter] = []
    ) -> ToolSpec {
        var properties = [String: any Sendable]()
        var required = [String]()

        for param in parameters {
            properties[param.name] = param.schema
            if param.isRequired {
                required.append(param.name)
            }
        }

        return [
            "type": "function",
            "function": [
                "name": name,
                "description": description,
                "parameters": [
                    "type": "object",
                    "properties": properties,
                    "required": required,
                ] as [String: any Sendable],
            ] as [String: any Sendable],
        ] as ToolSpec
    }

    // MARK: - Tool definitions

    static let timeToolSpec = makeTool(
        name: JarvisToolName.getCurrentDatetime.rawValue,
        description: "Restituisce la data e l'ora corrente. Usare sempre questo tool quando l'utente chiede che ora è o che giorno è."
    )

    static let getEventsSpec = makeTool(
        name: JarvisToolName.getEvents.rawValue,
        description: "Recupera gli eventi del calendario dell'utente nei prossimi giorni.",
        parameters: [
            .optional("days", type: .int, description: "Numero di giorni futuri da includere (default: 7)")
        ]
    )

    static let createEventSpec = makeTool(
        name: JarvisToolName.createEvent.rawValue,
        description: "Crea un nuovo evento nel calendario dell'utente.",
        parameters: [
            .required("title", type: .string, description: "Titolo dell'evento"),
            .required("start_date", type: .string, description: "Data e ora di inizio in formato yyyy-MM-dd'T'HH:mm (es: 2025-03-25T14:30)"),
            .optional("end_date", type: .string, description: "Data e ora di fine in formato yyyy-MM-dd'T'HH:mm. Default: 1 ora dopo l'inizio."),
            .optional("notes", type: .string, description: "Note aggiuntive per l'evento"),
        ]
    )

    static let createReminderSpec = makeTool(
        name: JarvisToolName.createReminder.rawValue,
        description: "Crea un nuovo promemoria.",
        parameters: [
            .required("title", type: .string, description: "Testo del promemoria"),
            .optional("due_date", type: .string, description: "Scadenza in formato yyyy-MM-dd'T'HH:mm (opzionale)"),
            .optional("notes", type: .string, description: "Note aggiuntive"),
        ]
    )

    static let getRemindersSpec = makeTool(
        name: JarvisToolName.getReminders.rawValue,
        description: "Recupera i promemoria attivi dell'utente."
    )

    static let getCurrentLocationSpec = makeTool(
        name: JarvisToolName.getCurrentLocation.rawValue,
        description: "Ottiene la posizione geografica corrente dell'utente (città, via) tramite GPS."
    )

    static let analyzeImageSpec = makeTool(
        name: JarvisToolName.analyzeImage.rawValue,
        description: "Analizza un'immagine usando la visione artificiale per estrarre testo (OCR) e classificare la scena.",
        parameters: [
            .required("source", type: .string, description: "Sorgente immagine: 'camera' per scattare una foto, 'library' per scegliere dalla libreria"),
            .optional("question", type: .string, description: "Domanda specifica sull'immagine (es: 'cosa c'è scritto?', 'cos'è questo?')"),
        ]
    )

    static let rememberSpec = makeTool(
        name: JarvisToolName.remember.rawValue,
        description: "Salva un'informazione importante sull'utente nella memoria persistente.",
        parameters: [
            .required("key", type: .string, description: "Etichetta breve per il fatto (es: 'nome', 'citta', 'colore_preferito')"),
            .required("content", type: .string, description: "Il contenuto da ricordare"),
        ]
    )

    static let recallSpec = makeTool(
        name: JarvisToolName.recall.rawValue,
        description: "Cerca nelle memorie salvate informazioni relative a un argomento.",
        parameters: [
            .required("query", type: .string, description: "Argomento da cercare nella memoria (es: 'nome', 'preferenze')"),
        ]
    )
}
