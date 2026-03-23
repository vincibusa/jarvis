import Foundation
import EventKit

final class ReminderTool {

    private let eventStore = EKEventStore()

    // MARK: - Access

    func requestAccess() async throws -> Bool {
        if #available(iOS 17.0, *) {
            return try await eventStore.requestFullAccessToReminders()
        } else {
            return try await withCheckedThrowingContinuation { continuation in
                eventStore.requestAccess(to: .reminder) { granted, error in
                    if let error = error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(returning: granted)
                    }
                }
            }
        }
    }

    // MARK: - Get reminders

    func getReminders() async throws -> String {
        let granted = try await requestAccess()
        guard granted else {
            return "Accesso ai promemoria negato."
        }

        let reminders: [EKReminder] = try await withCheckedThrowingContinuation { continuation in
            let predicate = eventStore.predicateForIncompleteReminders(
                withDueDateStarting: nil,
                ending: nil,
                calendars: nil
            )
            eventStore.fetchReminders(matching: predicate) { result in
                continuation.resume(returning: result ?? [])
            }
        }

        guard !reminders.isEmpty else {
            return "Nessun promemoria attivo."
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "it_IT")
        formatter.dateFormat = "d MMM, HH:mm"

        let lines = reminders.map { reminder -> String in
            let title = reminder.title ?? "(senza titolo)"
            if let components = reminder.dueDateComponents,
               let date = Calendar.current.date(from: components) {
                return "• \(title) — \(formatter.string(from: date))"
            }
            return "• \(title)"
        }

        return "Promemoria attivi:\n" + lines.joined(separator: "\n")
    }

    // MARK: - Create reminder

    func createReminder(
        title: String,
        dueDate: String? = nil,
        notes: String? = nil
    ) async throws -> String {
        let granted = try await requestAccess()
        guard granted else {
            return "Accesso ai promemoria negato."
        }

        let reminder = EKReminder(eventStore: eventStore)
        reminder.title = title
        reminder.notes = notes
        reminder.calendar = eventStore.defaultCalendarForNewReminders()

        if let dueDateStr = dueDate {
            let parser = DateFormatter()
            parser.locale = Locale(identifier: "en_US_POSIX")
            parser.dateFormat = "yyyy-MM-dd'T'HH:mm"
            if let date = parser.date(from: dueDateStr) {
                reminder.dueDateComponents = Calendar.current.dateComponents(
                    [.year, .month, .day, .hour, .minute],
                    from: date
                )
            }
        }

        try eventStore.save(reminder, commit: true)

        if let components = reminder.dueDateComponents,
           let date = Calendar.current.date(from: components) {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "it_IT")
            formatter.dateFormat = "d MMMM 'alle' HH:mm"
            return "Promemoria '\(title)' creato per il \(formatter.string(from: date))."
        }

        return "Promemoria '\(title)' creato."
    }
}
