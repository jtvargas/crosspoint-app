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
        .modelContainer(sharedModelContainer)
    }
}
