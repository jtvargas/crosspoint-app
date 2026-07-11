import SwiftData

/// Single source of truth for the app's SwiftData schema.
///
/// Every entry point that opens the shared on-disk store (the main app,
/// App Intents, extensions) MUST build its container from this schema.
/// Opening the store with a subset of the entities triggers an automatic
/// migration that silently DROPS the omitted entities' data — this is
/// exactly how saved RSS feeds were wiped whenever the Convert intent ran
/// outside the app (issue #20).
enum AppSchema {
    static let schema = Schema([
        Article.self,
        DeviceSettings.self,
        ActivityEvent.self,
        QueueItem.self,
        RSSFeed.self,
        RSSArticle.self,
    ])
}
