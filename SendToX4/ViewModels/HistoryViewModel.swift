import Foundation
import SwiftData

/// Manages article history operations.
@MainActor
@Observable
final class HistoryViewModel {

    var searchText = ""

    /// Delete an article from history.
    func delete(article: Article, from modelContext: ModelContext) {
        modelContext.delete(article)
    }

    /// Delete multiple articles by index set (for swipe-to-delete in lists).
    func delete(at offsets: IndexSet, from articles: [Article], modelContext: ModelContext) {
        for index in offsets {
            modelContext.delete(articles[index])
        }
    }

    /// Clear all article history.
    func clearAll(modelContext: ModelContext) {
        do {
            try modelContext.delete(model: Article.self)
        } catch {
            // Silently handle — history clearing is non-critical
        }
    }
}
