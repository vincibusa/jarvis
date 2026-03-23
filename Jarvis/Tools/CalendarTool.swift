import Foundation
import EventKit

final class CalendarTool {

    private let eventStore = EKEventStore()

    // MARK: - Access

    func requestAccess() async throws -> Bool {
        if #available(iOS 17.0, *) {
            return try await eventStore.requestFullAccessToEvents()
        } else {
            return try await withCheckedThrowingContinuation { continuation in
                eventStore.requestAccess(to: .event) { granted, error in
                    if let error = error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(returning: granted)
                    }
                }
            }
        }
    }

    // MARK: - Get events

    func getEvents(days: Int = 7) async throws -> String {
        let granted = try await requestAccess()
        guard granted else {
            return "Accesso al calendario negato."
        }

        let start = Date()
        let end = Calendar.current.date(byAdding: .day, value: days, to: start) ?? start

        let predicate = eventStore.predicateForEvents(
            withStart: start,
            end: end,
            calendars: nil
        )
        let events = eventStore.events(matching: predicate)
            .sorted { $0.startDate < $1.startDate }

        guard !events.isEmpty else {
            return "Nessun evento nei prossimi \(days) giorni."
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "it_IT")
        formatter.dateFormat = "EEEE d MMM, HH:mm"

        let lines = events.map { event -> String in
            let start = formatter.string(from: event.startDate)
            let title = event.title ?? "(senza titolo)"
            return "• \(title) — \(start)"
        }

        return "Prossimi eventi:\n" + lines.joined(separator: "\n")
    }

    // MARK: - Create event

    func createEvent(
        title: String,
        startDate: String,
        endDate: String? = nil,
        notes: String? = nil
    ) async throws -> String {
        let granted = try await requestAccess()
        guard granted else {
            return "Accesso al calendario negato."
        }

        let parser = DateFormatter()
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.dateFormat = "yyyy-MM-dd'T'HH:mm"

        guard let start = parser.date(from: startDate) else {
            return "Formato data non valido. Usa yyyy-MM-dd'T'HH:mm (es: 2025-03-25T14:30)."
        }

        let end: Date
        if let endStr = endDate, let parsedEnd = parser.date(from: endStr) {
            end = parsedEnd
        } else {
            end = Calendar.current.date(byAdding: .hour, value: 1, to: start) ?? start
        }

        let event = EKEvent(eventStore: eventStore)
        event.title = title
        event.startDate = start
        event.endDate = end
        event.notes = notes
        event.calendar = eventStore.defaultCalendarForNewEvents

        try eventStore.save(event, span: .thisEvent)

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "it_IT")
        formatter.dateFormat = "EEEE d MMMM 'alle' HH:mm"
        let formatted = formatter.string(from: start)

        return "Evento '\(title)' creato per \(formatted)."
    }
}
