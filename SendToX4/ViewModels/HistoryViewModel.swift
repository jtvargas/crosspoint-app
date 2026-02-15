import Foundation
import SwiftData

/// Manages history operations for both conversion articles and activity events.
@MainActor
@Observable
final class HistoryViewModel {

    var searchText = ""

    // MARK: - Badge / Unseen Tracking

    /// Timestamp of the last time the user viewed the History tab.
    /// Initialized to app launch time so the badge starts at 0.
    var lastHistoryViewedAt: Date = Date()

    /// Mark all current history as seen (resets the badge count to 0).
    func markAsSeen() {
        lastHistoryViewedAt = Date()
    }

    /// Count of log entries created after the user last viewed the History tab.
    func unseenCount(articles: [Article], activities: [ActivityEvent]) -> Int {
        let cutoff = lastHistoryViewedAt
        let newArticles = articles.filter { $0.createdAt > cutoff }.count
        let newActivities = activities.filter { $0.timestamp > cutoff }.count
        return newArticles + newActivities
    }

    // MARK: - Single Item Deletion

    /// Delete an article from history.
    func delete(article: Article, from modelContext: ModelContext) {
        modelContext.delete(article)
    }

    /// Delete an activity event from history.
    func delete(activity: ActivityEvent, from modelContext: ModelContext) {
        modelContext.delete(activity)
    }

    /// Delete multiple articles by index set (for swipe-to-delete in lists).
    func delete(at offsets: IndexSet, from articles: [Article], modelContext: ModelContext) {
        for index in offsets {
            modelContext.delete(articles[index])
        }
    }

    // MARK: - Granular Clear

    /// Clear only conversion history (Article records).
    func clearConversions(modelContext: ModelContext) {
        do {
            try modelContext.delete(model: Article.self)
        } catch {
            // Silently handle — history clearing is non-critical
        }
    }

    /// Clear only file activity history (ActivityEvent records).
    func clearActivities(modelContext: ModelContext) {
        do {
            try modelContext.delete(model: ActivityEvent.self)
        } catch {
            // Silently handle — history clearing is non-critical
        }
    }

    /// Clear all history (both articles and activity events).
    func clearAll(modelContext: ModelContext) {
        clearConversions(modelContext: modelContext)
        clearActivities(modelContext: modelContext)
    }
}
