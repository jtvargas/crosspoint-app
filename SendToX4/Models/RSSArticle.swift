import Foundation
import SwiftData

/// Represents the lifecycle state of an RSS article in the app.
enum RSSArticleStatus: String, Codable {
    /// Freshly fetched from the feed, not yet processed.
    case new
    /// Converted and added to the send queue.
    case queued
    /// Successfully sent to the device.
    case sent
    /// Conversion or send failed.
    case failed
}

/// Persisted record of an individual article fetched from an RSS feed.
///
/// Linked to its parent `RSSFeed` by `feedID` (not a SwiftData relationship,
/// to avoid tight coupling and keep the model independent from existing types).
@Model
final class RSSArticle {
    var id: UUID
    var feedID: UUID
    var title: String
    var articleURL: String
    var author: String?
    var summary: String?
    var publishedAt: Date?
    var domain: String
    var statusRaw: String
    var errorMessage: String?
    var fetchedAt: Date

    var status: RSSArticleStatus {
        get { RSSArticleStatus(rawValue: statusRaw) ?? .new }
        set { statusRaw = newValue.rawValue }
    }

    init(
        feedID: UUID,
        title: String,
        articleURL: String,
        author: String? = nil,
        summary: String? = nil,
        publishedAt: Date? = nil,
        domain: String
    ) {
        self.id = UUID()
        self.feedID = feedID
        self.title = title
        self.articleURL = articleURL
        self.author = author
        self.summary = summary
        self.publishedAt = publishedAt
        self.domain = domain
        self.statusRaw = RSSArticleStatus.new.rawValue
        self.fetchedAt = Date()
    }
}
