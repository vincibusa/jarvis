import Foundation
import MLXLMCommon
import Tokenizers

// MARK: - ToolParameter helper

struct ToolParameter {
    let name: String
    let schema: [String: any Sendable]
    let isRequired: Bool

    enum ParamType: String {
        case string = "string"
        case int = "integer"
        case number = "number"
        case bool = "boolean"
    }

    static func required(_ name: String, type: ParamType, description: String) -> ToolParameter {
        ToolParameter(
            name: name,
            schema: ["type": type.rawValue, "description": description] as [String: any Sendable],
            isRequired: true
        )
    }

    static func optional(_ name: String, type: ParamType, description: String) -> ToolParameter {
        ToolParameter(
            name: name,
            schema: ["type": type.rawValue, "description": description] as [String: any Sendable],
            isRequired: false
        )
    }
}

// MARK: - Tool names

enum JarvisToolName: String, CaseIterable {
    case getCurrentDatetime  = "get_current_datetime"
    case getEvents           = "get_events"
    case createEvent         = "create_event"
    case createReminder      = "create_reminder"
    case getReminders        = "get_reminders"
    case getCurrentLocation  = "get_current_location"
    case analyzeImage        = "analyze_image"
    case scanDocument        = "scan_document"
    case remember            = "remember"
    case recall              = "recall"
    case webSearch           = "web_search"
    case sendEmail           = "send_email"
    case transcribeAudio     = "transcribe_audio"
    case summarizeAudio      = "summarize_audio"
    case searchDocuments     = "search_documents"
    case listDocuments       = "list_documents"
    case createPdf           = "create_pdf"
    case createWord          = "create_word"
    case createExcel         = "create_excel"

    var displayName: String {
        switch self {
        case .getCurrentDatetime: return "Orologio"
        case .getEvents:          return "Calendario"
        case .createEvent:        return "Nuovo evento"
        case .createReminder:     return "Promemoria"
        case .getReminders:       return "Promemoria"
        case .getCurrentLocation: return "Posizione"
        case .analyzeImage:       return "Analisi immagine"
        case .scanDocument:       return "Scansione documento"
        case .remember:           return "Memoria"
        case .recall:             return "Ricordo"
        case .webSearch:          return "Ricerca web"
        case .sendEmail:          return "Invia email"
        case .transcribeAudio:    return "Trascrizione audio"
        case .summarizeAudio:     return "Riassunto audio"
        case .searchDocuments:    return "Cerca documenti"
        case .listDocuments:      return "Documenti"
        case .createPdf:          return "Crea PDF"
        case .createWord:         return "Crea Word"
        case .createExcel:        return "Crea Excel"
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
        case .scanDocument:       return "doc.viewfinder"
        case .remember:           return "brain.head.profile"
        case .recall:             return "brain"
        case .webSearch:          return "globe"
        case .sendEmail:          return "envelope"
        case .transcribeAudio:    return "waveform.and.mic"
        case .summarizeAudio:     return "text.quote"
        case .searchDocuments:    return "doc.text.magnifyingglass"
        case .listDocuments:      return "doc.stack"
        case .createPdf:          return "doc.richtext"
        case .createWord:         return "doc.text"
        case .createExcel:        return "tablecells"
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
            scanDocumentSpec,
            rememberSpec,
            recallSpec,
            webSearchSpec,
            sendEmailSpec,
            transcribeAudioSpec,
            summarizeAudioSpec,
            searchDocumentsSpec,
            listDocumentsSpec,
            createPdfSpec,
            createWordSpec,
            createExcelSpec,
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
        description: "Analizza un'immagine usando la visione artificiale per estrarre testo (OCR), classificare la scena e leggere codici QR/barcode.",
        parameters: [
            .required("source", type: .string, description: "Sorgente immagine: 'camera' per scattare una foto, 'library' per scegliere dalla libreria"),
            .optional("question", type: .string, description: "Domanda specifica sull'immagine (es: 'cosa c'è scritto?', 'cos'è questo?')"),
        ]
    )

    static let scanDocumentSpec = makeTool(
        name: JarvisToolName.scanDocument.rawValue,
        description: "Scansiona un documento cartaceo (ricevuta, fattura, documento) usando la fotocamera per estrarre il testo."
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

    static let webSearchSpec = makeTool(
        name: JarvisToolName.webSearch.rawValue,
        description: "Cerca informazioni sul web. Usa per notizie recenti, fatti, informazioni che non conosci.",
        parameters: [
            .required("query", type: .string, description: "La query di ricerca"),
        ]
    )

    static let sendEmailSpec = makeTool(
        name: JarvisToolName.sendEmail.rawValue,
        description: "Compone e invia un'email. Apre il compositore email con i campi precompilati.",
        parameters: [
            .required("to", type: .string, description: "Indirizzo email del destinatario"),
            .required("subject", type: .string, description: "Oggetto dell'email"),
            .required("body", type: .string, description: "Testo del corpo dell'email"),
        ]
    )

    static let transcribeAudioSpec = makeTool(
        name: JarvisToolName.transcribeAudio.rawValue,
        description: "Trascrive un file audio (nota vocale, registrazione) in testo usando il riconoscimento vocale on-device."
    )

    static let summarizeAudioSpec = makeTool(
        name: JarvisToolName.summarizeAudio.rawValue,
        description: "Trascrive e riassume un file audio. Utile per note vocali, podcast o registrazioni di riunioni."
    )

    static let searchDocumentsSpec = makeTool(
        name: JarvisToolName.searchDocuments.rawValue,
        description: "Cerca nei documenti importati dall'utente per trovare informazioni rilevanti.",
        parameters: [
            .required("query", type: .string, description: "La domanda o il testo da cercare nei documenti"),
            .optional("top_k", type: .int, description: "Numero massimo di risultati da restituire (default: 3)"),
        ]
    )

    static let listDocumentsSpec = makeTool(
        name: JarvisToolName.listDocuments.rawValue,
        description: "Elenca tutti i documenti importati dall'utente."
    )

    static let createPdfSpec = makeTool(
        name: JarvisToolName.createPdf.rawValue,
        description: """
        Crea un documento PDF. Usare per report, lettere, relazioni, riassunti. \
        Separare i paragrafi con \\n\\n. \
        Per intestazioni di sezione usare '## Titolo' su una riga a sé.
        """,
        parameters: [
            .required("title",   type: .string, description: "Titolo del documento"),
            .required("content", type: .string, description: "Contenuto completo. Paragrafi separati da \\n\\n, sezioni con '## Titolo'."),
            .optional("filename", type: .string, description: "Nome file senza estensione (default: il titolo)"),
        ]
    )

    static let createWordSpec = makeTool(
        name: JarvisToolName.createWord.rawValue,
        description: """
        Crea un documento Word (.docx) editabile. \
        Usare quando l'utente vuole modificare il documento in seguito. \
        Stessa formattazione del PDF: paragrafi con \\n\\n, sezioni con '## Titolo'.
        """,
        parameters: [
            .required("title",   type: .string, description: "Titolo del documento"),
            .required("content", type: .string, description: "Contenuto completo. Paragrafi separati da \\n\\n, sezioni con '## Titolo'."),
            .optional("filename", type: .string, description: "Nome file senza estensione (default: il titolo)"),
        ]
    )

    static let createExcelSpec = makeTool(
        name: JarvisToolName.createExcel.rawValue,
        description: """
        Crea un foglio Excel (.xlsx) con dati tabulari. \
        Usare per tabelle, elenchi strutturati, confronti, dati numerici. \
        Gli header vanno separati da virgola (es: 'Nome,Età,Città'). \
        Ogni riga dati va su una linea separata, celle separate da virgola \
        (es: 'Mario,30,Roma\\nLuigi,25,Milano'). I numeri vengono riconosciuti automaticamente.
        """,
        parameters: [
            .required("headers", type: .string, description: "Intestazioni colonne separate da virgola. Es: 'Prodotto,Quantità,Prezzo'"),
            .required("rows",    type: .string, description: "Righe dati: ogni riga su una linea (\\n), celle separate da virgola. Es: 'Mela,10,0.5\\nPera,5,0.8'"),
            .optional("title",   type: .string, description: "Nome del foglio (default: 'Foglio1')"),
            .optional("filename", type: .string, description: "Nome file senza estensione"),
        ]
    )
}
