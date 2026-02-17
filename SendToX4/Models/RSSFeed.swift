import Foundation
import SwiftData

/// Persisted RSS/Atom feed configuration.
///
/// Each feed stores its URL, display metadata, and fetch settings.
/// Articles fetched from this feed are stored as separate `RSSArticle` records
/// linked by `feedID`.
@Model
final class RSSFeed {
    var id: UUID
    var title: String
    var feedURL: String
    var domain: String
    var iconURL: String?
    var lastFetchedAt: Date?
    var isEnabled: Bool
    var createdAt: Date
    var maxItems: Int

    init(
        title: String,
        feedURL: String,
        domain: String,
        iconURL: String? = nil,
        isEnabled: Bool = true,
        maxItems: Int = 25
    ) {
        self.id = UUID()
        self.title = title
        self.feedURL = feedURL
        self.domain = domain
        self.iconURL = iconURL
        self.lastFetchedAt = nil
        self.isEnabled = isEnabled
        self.createdAt = Date()
        self.maxItems = maxItems
    }
}
