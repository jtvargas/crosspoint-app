import Foundation
import SwiftData

/// Manages RSS feed configuration, article fetching, selection, and batch conversion.
@MainActor
@Observable
final class RSSFeedViewModel {

    // MARK: - UI State

    /// Whether a feed refresh is in progress.
    var isRefreshing = false

    /// Whether a batch conversion/send is in progress.
    var isBatchProcessing = false

    /// Progress during batch processing: (current 1-based index, total count).
    var batchProgress: (current: Int, total: Int)?

    /// Error message from the last failed operation.
    var errorMessage: String?

    /// Success message shown temporarily after a completed action.
    var successMessage: String?

    /// Controls whether the RSS feed sheet is presented.
    var showFeedSheet = false

    /// The currently selected feed for filtering, or `nil` to show all.
    var selectedFeedID: UUID?

    /// IDs of articles selected for batch processing.
    var selectedArticleIDs: Set<UUID> = []

    /// Whether the add-feed form is being validated.
    var isValidatingFeed = false

    /// The count of new (unprocessed) articles across all feeds.
    var newArticleCount = 0

    // MARK: - Private

    private let readabilityExtractor = ReadabilityExtractor()

    // MARK: - Feed Management

    /// Add a new feed from a URL string. Supports both direct feed URLs and website URLs
    /// (auto-discovers the feed via `<link rel="alternate">`).
    func addFeed(urlString: String, modelContext: ModelContext) async {
        var cleaned = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleaned.contains("://") {
            cleaned = "https://" + cleaned
        }
        guard let url = URL(string: cleaned) else {
            errorMessage = loc(.rssInvalidFeedURL)
            return
        }

        isValidatingFeed = true
        errorMessage = nil

        do {
            // First, try the URL as a direct feed
            var feedURL = url
            var parsedFeed: RSSFeedService.ParsedFeed

            do {
                parsedFeed = try await RSSFeedService.validate(url: feedURL)
            } catch {
                // Not a direct feed — try discovering from website HTML
                guard let discoveredURL = try await RSSFeedService.discoverFeed(from: url) else {
                    throw RSSFeedService.RSSError.noFeedFound
                }
                feedURL = discoveredURL
                parsedFeed = try await RSSFeedService.validate(url: feedURL)
            }

            let domain = feedURL.host ?? url.host ?? "unknown"
            let title = parsedFeed.title.isEmpty ? domain : parsedFeed.title

            // Check for duplicate feed URL
            let feedURLString = feedURL.absoluteString
            let descriptor = FetchDescriptor<RSSFeed>(
                predicate: #Predicate<RSSFeed> { $0.feedURL == feedURLString }
            )
            if let existing = try? modelContext.fetch(descriptor).first {
                errorMessage = loc(.rssFeedAlreadyExists, existing.title)
                isValidatingFeed = false
                return
            }

            let feed = RSSFeed(
                title: title,
                feedURL: feedURLString,
                domain: domain
            )
            modelContext.insert(feed)

            // Fetch initial articles
            await ingestItems(parsedFeed.items, for: feed, modelContext: modelContext)

            isValidatingFeed = false
        } catch {
            errorMessage = error.localizedDescription
            isValidatingFeed = false
        }
    }

    /// Remove a feed and all its articles.
    func removeFeed(_ feed: RSSFeed, modelContext: ModelContext) {
        let feedID = feed.id
        // Delete all articles for this feed
        let descriptor = FetchDescriptor<RSSArticle>(
            predicate: #Predicate<RSSArticle> { $0.feedID == feedID }
        )
        if let articles = try? modelContext.fetch(descriptor) {
            for article in articles {
                modelContext.delete(article)
            }
        }
        modelContext.delete(feed)

        // Clear selection if viewing this feed
        if selectedFeedID == feedID {
            selectedFeedID = nil
        }
    }

    /// Toggle a feed's enabled state.
    func toggleFeed(_ feed: RSSFeed) {
        feed.isEnabled.toggle()
    }

    // MARK: - Fetching

    /// Refresh all enabled feeds. Called on app launch and pull-to-refresh.
    func refreshAllFeeds(modelContext: ModelContext) async {
        let descriptor = FetchDescriptor<RSSFeed>(
            predicate: #Predicate<RSSFeed> { $0.isEnabled == true }
        )
        guard let feeds = try? modelContext.fetch(descriptor), !feeds.isEmpty else { return }

        isRefreshing = true
        errorMessage = nil

        for feed in feeds {
            await refreshFeed(feed, modelContext: modelContext)
        }

        updateNewArticleCount(modelContext: modelContext)
        isRefreshing = false
    }

    /// Refresh a single feed — fetch new items and deduplicate.
    func refreshFeed(_ feed: RSSFeed, modelContext: ModelContext) async {
        guard let url = URL(string: feed.feedURL) else { return }

        do {
            let parsedFeed = try await RSSFeedService.fetch(url: url)
            await ingestItems(parsedFeed.items, for: feed, modelContext: modelContext)
            feed.lastFetchedAt = Date()
            DebugLogger.log(
                "Refreshed feed '\(feed.title)': \(parsedFeed.items.count) item(s) fetched",
                level: .info, category: .rss
            )
        } catch {
            DebugLogger.log(
                "Failed to refresh feed '\(feed.title)': \(error.localizedDescription)",
                level: .error, category: .rss
            )
            // Silently skip failed feeds during batch refresh
            // Individual feed errors don't block other feeds
        }
    }

    // MARK: - Selection

    /// Toggle selection of a single article.
    func toggleSelection(_ articleID: UUID) {
        if selectedArticleIDs.contains(articleID) {
            selectedArticleIDs.remove(articleID)
        } else {
            selectedArticleIDs.insert(articleID)
        }
    }

    /// Select all articles currently visible (those with `.new` status in the filtered list).
    func selectAllNew(modelContext: ModelContext) {
        let articles = fetchFilteredArticles(modelContext: modelContext)
        let newIDs = articles
            .filter { $0.status == .new }
            .map(\.id)
        selectedArticleIDs = Set(newIDs)
    }

    /// Deselect all articles.
    func deselectAll() {
        selectedArticleIDs.removeAll()
    }

    // MARK: - Batch Processing

    /// Convert selected articles to EPUB and send/queue them.
    ///
    /// If the device is connected, sends directly to `/feed/<domain>/`.
    /// If disconnected, enqueues for later sending.
    func sendSelected(
        deviceVM: DeviceViewModel,
        queueVM: QueueViewModel,
        settings: DeviceSettings,
        modelContext: ModelContext
    ) async {
        let selectedIDs = selectedArticleIDs
        guard !selectedIDs.isEmpty else { return }

        // Fetch the selected RSSArticle records
        let descriptor = FetchDescriptor<RSSArticle>()
        guard let allArticles = try? modelContext.fetch(descriptor) else { return }
        let articlesToProcess = allArticles.filter { selectedIDs.contains($0.id) }

        guard !articlesToProcess.isEmpty else { return }

        isBatchProcessing = true
        errorMessage = nil
        successMessage = nil
        batchProgress = (0, articlesToProcess.count)

        DebugLogger.log(
            "RSS batch send started: \(articlesToProcess.count) article(s), device \(deviceVM.isConnected ? "connected" : "disconnected")",
            level: .info, category: .rss
        )

        var sentCount = 0
        var queuedCount = 0
        var failCount = 0

        for (index, rssArticle) in articlesToProcess.enumerated() {
            batchProgress = (index + 1, articlesToProcess.count)

            guard let articleURL = URL(string: rssArticle.articleURL) else {
                rssArticle.status = .failed
                rssArticle.errorMessage = loc(.rssInvalidURL)
                failCount += 1

                // Create a failed Article record for history tracking
                let failedArticle = Article(
                    url: rssArticle.articleURL,
                    title: rssArticle.title,
                    author: rssArticle.author,
                    sourceDomain: rssArticle.domain
                )
                failedArticle.status = .failed
                failedArticle.errorMessage = loc(.rssInvalidURL)
                modelContext.insert(failedArticle)

                // Log per-failure ActivityEvent
                let event = ActivityEvent(
                    category: .rss,
                    action: .rssConversion,
                    status: .failed,
                    detail: rssArticle.title,
                    errorMessage: loc(.rssInvalidURL)
                )
                modelContext.insert(event)

                DebugLogger.log(
                    "RSS article \(index + 1)/\(articlesToProcess.count): invalid URL '\(rssArticle.articleURL)'",
                    level: .error, category: .rss
                )
                continue
            }

            // Track article outside do block so catch can reference it
            var article: Article?

            do {
                // Fetch HTML
                let page = try await WebPageFetcher.fetch(url: articleURL)

                // Extract content (same multi-strategy pipeline as ConvertViewModel)
                let content = try await extractContent(html: page.html, url: page.finalURL)

                // Build EPUB
                let metadata = EPUBBuilder.Metadata(
                    title: content.title,
                    author: content.author ?? "Unknown",
                    language: content.language,
                    sourceURL: page.finalURL,
                    description: content.description
                )
                let epubData = try EPUBBuilder.build(body: content.bodyHTML, metadata: metadata)
                let filename = FileNameGenerator.generate(
                    title: content.title, author: content.author, url: page.finalURL
                )

                // Create an Article record for history tracking
                let newArticle = Article(
                    url: rssArticle.articleURL,
                    title: content.title,
                    author: content.author,
                    sourceDomain: rssArticle.domain
                )
                modelContext.insert(newArticle)
                article = newArticle

                // Destination folder: /feed/<domain>/
                let destFolder = "feed/\(rssArticle.domain)"

                if deviceVM.isConnected && !deviceVM.isBatchDeleting {
                    // Send directly
                    try await deviceVM.upload(
                        data: epubData,
                        filename: filename,
                        toFolder: destFolder
                    )
                    newArticle.status = .sent
                    rssArticle.status = .sent
                    sentCount += 1
                    DebugLogger.log(
                        "RSS article \(index + 1)/\(articlesToProcess.count) sent: \(filename) -> /\(destFolder)/",
                        level: .info, category: .rss
                    )
                } else {
                    // Enqueue for later
                    try QueueViewModel.enqueueEPUB(
                        epubData: epubData,
                        filename: filename,
                        article: newArticle,
                        modelContext: modelContext,
                        destinationFolder: destFolder,
                        rssArticleID: rssArticle.id
                    )
                    newArticle.status = .savedLocally
                    rssArticle.status = .queued
                    queuedCount += 1
                    DebugLogger.log(
                        "RSS article \(index + 1)/\(articlesToProcess.count) queued: \(filename)",
                        level: .info, category: .rss
                    )
                }

            } catch {
                rssArticle.status = .failed
                rssArticle.errorMessage = error.localizedDescription
                failCount += 1

                // Update or create Article record with failed status
                if let existingArticle = article {
                    existingArticle.status = .failed
                    existingArticle.errorMessage = error.localizedDescription
                } else {
                    let failedArticle = Article(
                        url: rssArticle.articleURL,
                        title: rssArticle.title,
                        author: rssArticle.author,
                        sourceDomain: rssArticle.domain
                    )
                    failedArticle.status = .failed
                    failedArticle.errorMessage = error.localizedDescription
                    modelContext.insert(failedArticle)
                }

                // Log per-failure ActivityEvent
                let event = ActivityEvent(
                    category: .rss,
                    action: .rssConversion,
                    status: .failed,
                    detail: rssArticle.title,
                    errorMessage: error.localizedDescription
                )
                modelContext.insert(event)

                DebugLogger.log(
                    "RSS article \(index + 1)/\(articlesToProcess.count) failed: \(rssArticle.title) — \(error.localizedDescription)",
                    level: .error, category: .rss
                )
            }
        }

        // Summary message
        if sentCount > 0 && queuedCount == 0 {
            successMessage = loc(.rssSentArticles, sentCount)
        } else if queuedCount > 0 && sentCount == 0 {
            successMessage = loc(.rssQueuedArticles, queuedCount)
        } else if sentCount > 0 && queuedCount > 0 {
            successMessage = loc(.rssSentAndQueued, sentCount, queuedCount)
        }

        if failCount > 0 {
            errorMessage = loc(.rssFailedArticles, failCount)
        }

        // Log activity event for batch
        if sentCount > 0 || queuedCount > 0 {
            let detail: String
            if sentCount > 0 {
                detail = loc(.rssSentArticles, sentCount)
            } else {
                detail = loc(.rssQueuedArticles, queuedCount)
            }
            let event = ActivityEvent(
                category: .queue,
                action: .queueSend,
                status: failCount == 0 ? .success : .failed,
                detail: "RSS: \(detail)"
            )
            modelContext.insert(event)
        }

        DebugLogger.log(
            "RSS batch complete: \(sentCount) sent, \(queuedCount) queued, \(failCount) failed",
            level: failCount == 0 ? .info : .warning, category: .rss
        )

        selectedArticleIDs.removeAll()
        updateNewArticleCount(modelContext: modelContext)
        isBatchProcessing = false
        batchProgress = nil
    }

    // MARK: - Data Access Helpers

    /// Fetch articles filtered by the currently selected feed.
    func fetchFilteredArticles(modelContext: ModelContext) -> [RSSArticle] {
        let descriptor: FetchDescriptor<RSSArticle>
        if let feedID = selectedFeedID {
            descriptor = FetchDescriptor<RSSArticle>(
                predicate: #Predicate<RSSArticle> { $0.feedID == feedID },
                sortBy: [SortDescriptor(\.publishedAt, order: .reverse)]
            )
        } else {
            descriptor = FetchDescriptor<RSSArticle>(
                sortBy: [SortDescriptor(\.publishedAt, order: .reverse)]
            )
        }
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    /// Fetch all feeds sorted by creation date.
    func fetchFeeds(modelContext: ModelContext) -> [RSSFeed] {
        let descriptor = FetchDescriptor<RSSFeed>(
            sortBy: [SortDescriptor(\.createdAt)]
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    /// Update the cached count of new articles.
    func updateNewArticleCount(modelContext: ModelContext) {
        let newStatus = RSSArticleStatus.new.rawValue
        let descriptor = FetchDescriptor<RSSArticle>(
            predicate: #Predicate<RSSArticle> { $0.statusRaw == newStatus }
        )
        newArticleCount = (try? modelContext.fetchCount(descriptor)) ?? 0
    }

    // MARK: - Private: Content Extraction

    /// Multi-strategy extraction: Twitter API -> SwiftSoup -> Readability.js fallback.
    /// Mirrors `ConvertViewModel.extractContent` to reuse the same pipeline.
    private func extractContent(html: String, url: URL) async throws -> ExtractedContent {
        if TwitterExtractor.canHandle(url: url) {
            if let content = try await TwitterExtractor.extract(from: url) {
                return content
            }
        }

        if let content = try ContentExtractor.extract(from: html, url: url) {
            return content
        }

        if let content = try await readabilityExtractor.extract(html: html, baseURL: url) {
            return content
        }

        throw EPUBError.contentTooShort
    }

    // MARK: - Private: Article Ingestion

    /// Ingest parsed items into SwiftData, deduplicating by article URL.
    private func ingestItems(
        _ items: [RSSFeedService.ParsedItem],
        for feed: RSSFeed,
        modelContext: ModelContext
    ) async {
        let feedID = feed.id

        // Fetch existing article URLs for this feed to deduplicate
        let descriptor = FetchDescriptor<RSSArticle>(
            predicate: #Predicate<RSSArticle> { $0.feedID == feedID }
        )
        let existingURLs: Set<String>
        if let existing = try? modelContext.fetch(descriptor) {
            existingURLs = Set(existing.map(\.articleURL))
        } else {
            existingURLs = []
        }

        // Insert new articles (up to feed.maxItems), skipping duplicates
        let newItems = items
            .filter { !$0.link.isEmpty && !existingURLs.contains($0.link) }
            .prefix(feed.maxItems)

        for item in newItems {
            let article = RSSArticle(
                feedID: feedID,
                title: item.title.isEmpty ? loc(.untitled) : item.title,
                articleURL: item.link,
                author: item.author,
                summary: item.summary?.prefix(500).description,
                publishedAt: item.publishedDate,
                domain: feed.domain
            )
            modelContext.insert(article)
        }

        // Trim old articles if we exceed maxItems
        let allDescriptor = FetchDescriptor<RSSArticle>(
            predicate: #Predicate<RSSArticle> { $0.feedID == feedID },
            sortBy: [SortDescriptor(\.publishedAt, order: .reverse)]
        )
        if let allArticles = try? modelContext.fetch(allDescriptor),
           allArticles.count > feed.maxItems {
            let excess = allArticles.suffix(from: feed.maxItems)
            for article in excess {
                // Only trim articles that have been processed (not new ones)
                if article.status != .new {
                    modelContext.delete(article)
                }
            }
        }
    }
}
