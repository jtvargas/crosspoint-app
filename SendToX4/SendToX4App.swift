//
//  SendToX4App.swift
//  SendToX4
//
//  Created by Jonathan Taveras Vargas on 2/13/26.
//

import SwiftUI
import SwiftData

@main
struct SendToX4App: App {
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Article.self,
            DeviceSettings.self,
            ActivityEvent.self,
            QueueItem.self,
            RSSFeed.self,
            RSSArticle.self,
        ])
        let modelConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false
        )

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    init() {
        ReviewPromptManager.registerFirstLaunchIfNeeded()
    }

    var body: some Scene {
        WindowGroup {
            LanguageBootstrap(container: sharedModelContainer) {
                MainView()
                    #if os(iOS)
                    .fullScreenCover(isPresented: Binding(
                        get: { !hasSeenOnboarding },
                        set: { if !$0 { hasSeenOnboarding = true } }
                    )) {
                        OnboardingView(hasSeenOnboarding: $hasSeenOnboarding)
                    }
                    #else
                    .sheet(isPresented: Binding(
                        get: { !hasSeenOnboarding },
                        set: { if !$0 { hasSeenOnboarding = true } }
                    )) {
                        OnboardingView(hasSeenOnboarding: $hasSeenOnboarding)
                            .frame(width: 520, height: 640)
                    }
                    #endif
            }
        }
        .modelContainer(sharedModelContainer)
    }
}

// MARK: - Language Bootstrap

/// Reads the persisted `DeviceSettings.languageCode` on launch and keeps
/// `LocalizationManager.shared.currentLanguage` in sync. Also applies
/// `.environment(\.locale, ...)` so SwiftUI system components (date formatters,
/// plurals, etc.) honour the override.
private struct LanguageBootstrap<Content: View>: View {
    let container: ModelContainer
    @ViewBuilder let content: Content

    @State private var locManager = LocalizationManager.shared

    var body: some View {
        content
            .environment(\.locale, locManager.locale)
            .onAppear {
                syncLanguageFromSettings()
            }
    }

    private func syncLanguageFromSettings() {
        let context = ModelContext(container)
        let descriptor = FetchDescriptor<DeviceSettings>()
        if let settings = try? context.fetch(descriptor).first {
            let lang = AppLanguage(rawValue: settings.languageCode) ?? .system
            LocalizationManager.shared.currentLanguage = lang
        }
    }
}
