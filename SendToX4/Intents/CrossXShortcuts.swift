import AppIntents

/// Registers pre-built Siri Shortcuts phrases for the CrossX app.
///
/// These appear automatically in the Shortcuts app under the CrossX section
/// and can be invoked by voice via Siri.
struct CrossXShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ConvertURLIntent(),
            phrases: [
                "Convert a page with \(.applicationName)",
                "Send to \(.applicationName)",
                "Queue a page in \(.applicationName)",
                "Convert URL with \(.applicationName)",
            ],
            shortTitle: "Convert to EPUB",
            systemImageName: "doc.text"
        )
    }
}
