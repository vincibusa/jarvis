import SwiftUI

enum JarvisTheme {
    // Colors
    static let accent       = Color(hex: "007AFF")
    static let userBubble   = Color(hex: "007AFF")
    static let assistantBubble = Color(hex: "2C2C2E")
    static let toolBubble   = Color(hex: "1C1C1E")
    static let background   = Color(hex: "000000")
    static let inputBackground = Color(hex: "1C1C1E")
    static let statusGreen  = Color(hex: "30D158")
    static let statusOrange = Color.orange

    // Fonts
    static let headerFont   = Font.system(.title2, design: .monospaced).bold()
    static let monoSmall    = Font.system(.caption, design: .monospaced)
    static let bubbleFont   = Font.system(.body)

    // Spacing
    static let bubblePadding: CGFloat = 12
    static let cornerRadius: CGFloat = 18
}

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3:
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}
