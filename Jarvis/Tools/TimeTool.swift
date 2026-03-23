import Foundation

enum TimeTool {
    static func getCurrentDatetime() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "it_IT")
        formatter.dateFormat = "HH:mm 'di' EEEE d MMMM yyyy"
        let formatted = formatter.string(from: Date())
        return "Sono le \(formatted)"
    }
}
