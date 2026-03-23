import AppIntents

struct JarvisShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AskJarvisIntent(),
            phrases: [
                "Chiedi a \(.applicationName) \(\.$question)",
                "Domanda per \(.applicationName) \(\.$question)",
                "Chiedi a \(.applicationName)",
                "Parla con \(.applicationName)"
            ],
            shortTitle: "Chiedi a Jarvis",
            systemImageName: "waveform"
        )
    }
}
