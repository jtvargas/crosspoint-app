import Foundation
import SwiftData

/// Manages the EPUB send queue — enqueuing files when offline, batch-sending when connected.
@MainActor
@Observable
final class QueueViewModel {

    // MARK: - UI State

    /// Whether a batch send is currently in progress.
    var isSending = false

    /// Progress during batch send: (current 1-based index, total count).
    var sendProgress: (current: Int, total: Int)?

    /// Name of the file currently being sent.
    var currentFilename: String?

    /// Error message from the last failed operation.
    var errorMessage: String?

    // MARK: - Queue Directory

    /// URL of the persistent queue directory inside Application Support.
    static var queueDirectoryURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("EPUBQueue")
    }

    /// Ensure the queue directory exists on disk.
    static func ensureQueueDirectory() throws {
        let url = queueDirectoryURL
        if !FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
    }

    // MARK: - Enqueue (Shared)

    /// Write EPUB data to disk and create a QueueItem record.
    ///
    /// This is a static helper so it can be called from both the ViewModel
    /// and headless contexts (e.g. App Intents, Share Extension).
    @discardableResult
    static func enqueueEPUB(
        epubData: Data,
        filename: String,
        article: Article,
        modelContext: ModelContext,
        destinationFolder: String? = nil,
        rssArticleID: UUID? = nil
    ) throws -> QueueItem {
        try ensureQueueDirectory()

        let itemID = UUID()
        let relativePath = "EPUBQueue/\(itemID.uuidString).epub"
        let fileURL = queueDirectoryURL.appendingPathComponent("\(itemID.uuidString).epub")

        try epubData.write(to: fileURL)

        let item = QueueItem(
            articleID: article.id,
            title: article.title.isEmpty ? loc(.untitled) : article.title,
            filename: filename,
            filePath: relativePath,
            fileSize: Int64(epubData.count),
            sourceURL: article.url,
            sourceDomain: article.sourceDomain,
            destinationFolder: destinationFolder,
            rssArticleID: rssArticleID
        )
        item.id = itemID
        modelContext.insert(item)
        return item
    }

    // MARK: - Enqueue (Instance)

    /// Convenience wrapper that captures errors into `errorMessage`.
    func enqueue(
        epubData: Data,
        filename: String,
        article: Article,
        modelContext: ModelContext
    ) {
        do {
            try Self.enqueueEPUB(
                epubData: epubData,
                filename: filename,
                article: article,
                modelContext: modelContext
            )
        } catch {
            errorMessage = loc(.failedToQueueEPUB, error.localizedDescription)
        }
    }

    // MARK: - Send All

    /// Cooldown between sequential sends (seconds). Gives the ESP32 time to recover.
    private static let itemCooldown: Duration = .seconds(2)

    /// Maximum retry attempts per item before marking as failed.
    private static let maxItemRetries = 1

    /// Delay before retrying a failed item.
    private static let retryDelay: Duration = .seconds(2)

    /// Number of consecutive failures before aborting the batch (device probably gone).
    private static let circuitBreakerThreshold = 3

    /// Send all queued items to the device sequentially with retry, cooldown,
    /// and circuit-breaker logic.
    func sendAll(
        deviceVM: DeviceViewModel,
        settings: DeviceSettings,
        modelContext: ModelContext
    ) async {
        let descriptor = FetchDescriptor<QueueItem>(sortBy: [SortDescriptor(\.queuedAt)])
        guard let items = try? modelContext.fetch(descriptor), !items.isEmpty else { return }

        isSending = true
        errorMessage = nil
        sendProgress = (0, items.count)

        let defaultFolder = settings.convertFolder
        var sentFilenames: [String] = []
        var failCount = 0
        var consecutiveFailures = 0

        DebugLogger.log(
            "Queue batch send started: \(items.count) item(s)",
            level: .info, category: .queue
        )

        for (index, item) in items.enumerated() {
            // Circuit breaker: abort if too many consecutive failures
            if consecutiveFailures >= Self.circuitBreakerThreshold {
                let remaining = items.count - index
                DebugLogger.log(
                    "Circuit breaker tripped after \(consecutiveFailures) consecutive failures. Aborting batch, \(remaining) item(s) remaining.",
                    level: .error, category: .queue
                )
                errorMessage = loc(.queueCircuitBreaker, consecutiveFailures)
                break
            }

            sendProgress = (index + 1, items.count)
            currentFilename = item.filename

            let folder = item.destinationFolder ?? defaultFolder
            var itemSent = false

            // Attempt with retry
            for attempt in 0...Self.maxItemRetries {
                if attempt > 0 {
                    DebugLogger.log(
                        "Retry \(attempt)/\(Self.maxItemRetries) for \(item.filename)",
                        level: .warning, category: .queue
                    )
                    try? await Task.sleep(for: Self.retryDelay)
                }

                do {
                    let data = try Data(contentsOf: item.fileURL)

                    DebugLogger.log(
                        "Sending item \(index + 1)/\(items.count): \(item.filename) -> /\(folder)/",
                        level: .info, category: .queue
                    )

                    try await deviceVM.upload(data: data, filename: item.filename, toFolder: folder)

                    sentFilenames.append(item.filename)
                    consecutiveFailures = 0 // Reset on success

                    // Update linked Article status to .sent
                    updateArticleStatus(articleID: item.articleID, to: .sent, modelContext: modelContext)

                    // Update linked RSSArticle status to .sent (if this was an RSS-originated item)
                    if let rssID = item.rssArticleID {
                        updateRSSArticleStatus(rssArticleID: rssID, to: .sent, modelContext: modelContext)
                    }

                    // Delete file from disk
                    try? FileManager.default.removeItem(at: item.fileURL)

                    // Delete QueueItem record
                    modelContext.delete(item)

                    DebugLogger.log(
                        "Sent item \(index + 1)/\(items.count): \(item.filename)",
                        level: .info, category: .queue
                    )

                    itemSent = true
                    break // Success — exit retry loop
                } catch {
                    DebugLogger.log(
                        "Failed item \(index + 1)/\(items.count) (attempt \(attempt + 1)): \(item.filename) — \(error.localizedDescription)",
                        level: .error, category: .queue
                    )

                    if attempt == Self.maxItemRetries {
                        // All retries exhausted for this item
                        failCount += 1
                        consecutiveFailures += 1
                        errorMessage = loc(.failedToSendItem, item.filename, error.localizedDescription)
                    }
                }
            }

            // Cooldown between items (skip after the last item)
            if index < items.count - 1 && itemSent {
                try? await Task.sleep(for: Self.itemCooldown)
            }
        }

        // Log a single ActivityEvent summarizing the batch
        if !sentFilenames.isEmpty {
            let detail: String
            if sentFilenames.count == 1 {
                detail = loc(.sentItem, sentFilenames[0])
            } else {
                let names = sentFilenames.prefix(3).joined(separator: ", ")
                let suffix = sentFilenames.count > 3 ? " and \(sentFilenames.count - 3) more" : ""
                detail = loc(.sentMultipleEPUBs, sentFilenames.count, names + suffix)
            }
            let event = ActivityEvent(
                category: .queue,
                action: .queueSend,
                status: failCount == 0 ? .success : .failed,
                detail: detail
            )
            modelContext.insert(event)
        }

        DebugLogger.log(
            "Queue batch complete: \(sentFilenames.count) sent, \(failCount) failed",
            level: failCount == 0 ? .info : .warning, category: .queue
        )

        isSending = false
        sendProgress = nil
        currentFilename = nil
    }

    // MARK: - Remove Single Item

    /// Remove a single item from the queue (delete file + record).
    func remove(_ item: QueueItem, modelContext: ModelContext) {
        try? FileManager.default.removeItem(at: item.fileURL)
        modelContext.delete(item)
    }

    // MARK: - Clear All

    /// Delete all queued items (files + records).
    func clearAll(modelContext: ModelContext) {
        // Delete all files in the queue directory
        let dirURL = Self.queueDirectoryURL
        if let contents = try? FileManager.default.contentsOfDirectory(
            at: dirURL, includingPropertiesForKeys: nil
        ) {
            for fileURL in contents {
                try? FileManager.default.removeItem(at: fileURL)
            }
        }

        // Delete all QueueItem records
        do {
            try modelContext.delete(model: QueueItem.self)
        } catch {
            // Silently handle — clearing is non-critical
        }
    }

    // MARK: - Private

    /// Find and update the Article linked to a queue item.
    private func updateArticleStatus(
        articleID: UUID,
        to status: ConversionStatus,
        modelContext: ModelContext
    ) {
        let descriptor = FetchDescriptor<Article>(
            predicate: #Predicate<Article> { $0.id == articleID }
        )
        if let article = try? modelContext.fetch(descriptor).first {
            article.status = status
        }
    }

    /// Find and update the RSSArticle linked to a queue item.
    /// This ensures RSS articles transition from `.queued` to `.sent`
    /// after the queue sender successfully uploads them to the device.
    private func updateRSSArticleStatus(
        rssArticleID: UUID,
        to status: RSSArticleStatus,
        modelContext: ModelContext
    ) {
        let descriptor = FetchDescriptor<RSSArticle>(
            predicate: #Predicate<RSSArticle> { $0.id == rssArticleID }
        )
        if let rssArticle = try? modelContext.fetch(descriptor).first {
            rssArticle.status = status
            DebugLogger.log(
                "Updated RSS article status to .\(status.rawValue): \(rssArticle.title)",
                level: .info, category: .rss
            )
        }
    }
}
