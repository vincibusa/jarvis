import AppIntents

struct JarvisShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AskJarvisIntent(),
            phrases: [
                // Siri will prompt the user for the question (String params can't be captured in phrases)
                "Chiedi a \(.applicationName)",
                "Parla con \(.applicationName)",
                "Domanda per \(.applicationName)"
            ],
            shortTitle: "Chiedi a Jarvis",
            systemImageName: "waveform"
        )
    }
}
