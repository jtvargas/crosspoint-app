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

    // MARK: - Individual Send State

    /// Ordered IDs of items the user has tapped to send individually.
    /// Items are processed sequentially in FIFO order.
    var pendingSendIDs: [UUID] = []

    /// Whether the individual-send loop is actively running.
    var isSendingSingle = false

    // MARK: - Duplicate Detection

    /// Check whether a URL is already in the send queue.
    ///
    /// Compares normalized URLs to catch trivial variations (trailing slash,
    /// http vs https, www vs non-www, URL fragments).
    static func isURLQueued(_ urlString: String, modelContext: ModelContext) -> Bool {
        let normalized = normalizeURL(urlString)
        let descriptor = FetchDescriptor<QueueItem>()
        guard let items = try? modelContext.fetch(descriptor) else { return false }
        return items.contains { normalizeURL($0.sourceURL) == normalized }
    }

    /// Normalize a URL for duplicate comparison:
    /// - Lowercase scheme and host
    /// - Strip `www.` prefix
    /// - Strip fragment (`#...`)
    /// - Strip trailing `/` from path
    /// - Normalize `http://` to `https://`
    private static func normalizeURL(_ urlString: String) -> String {
        guard var components = URLComponents(string: urlString) else {
            return urlString.lowercased()
        }
        // Normalize scheme
        components.scheme = (components.scheme?.lowercased() == "http") ? "https" : components.scheme?.lowercased()
        // Normalize host: lowercase + strip www.
        if var host = components.host?.lowercased() {
            if host.hasPrefix("www.") {
                host = String(host.dropFirst(4))
            }
            components.host = host
        }
        // Strip fragment
        components.fragment = nil
        // Strip trailing slash from path
        if components.path.hasSuffix("/") && components.path != "/" {
            components.path = String(components.path.dropLast())
        }
        return components.string?.lowercased() ?? urlString.lowercased()
    }

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

    /// Maximum retry attempts per item before marking as failed.
    private static let maxItemRetries = 1

    /// Delay before retrying a failed item.
    private static let retryDelay: Duration = .seconds(2)

    /// Number of consecutive failures before aborting the batch (device probably gone).
    private static let circuitBreakerThreshold = 3

    /// Adaptive cooldown between sequential sends based on file size.
    /// Small files need minimal ESP32 recovery time; larger files need more.
    private static func cooldown(forFileSize bytes: Int64) -> Duration {
        switch bytes {
        case ..<50_000:    return .milliseconds(300)   // < 50 KB — tiny EPUB
        case ..<200_000:   return .milliseconds(800)   // < 200 KB — typical article
        default:           return .milliseconds(1_500)  // >= 200 KB — long/image-heavy
        }
    }

    /// Returns the cooldown in seconds for a given file size.
    /// Mirrors the `cooldown(forFileSize:)` Duration function for use in estimation.
    private static func cooldownSeconds(forFileSize bytes: Int64) -> Double {
        switch bytes {
        case ..<50_000:    return 0.3
        case ..<200_000:   return 0.8
        default:           return 1.5
        }
    }

    /// Send all queued items to the device sequentially with retry, cooldown,
    /// and circuit-breaker logic.
    func sendAll(
        deviceVM: DeviceViewModel,
        settings: DeviceSettings,
        modelContext: ModelContext
    ) async {
        let descriptor = FetchDescriptor<QueueItem>(sortBy: [SortDescriptor(\.queuedAt)])
        guard let items = try? modelContext.fetch(descriptor), !items.isEmpty else { return }
        guard !isSendingSingle else {
            DebugLogger.log("Queue sendAll blocked: individual sends in progress", level: .warning, category: .queue)
            return
        }
        guard !deviceVM.isBatchDeleting else {
            DebugLogger.log("Queue send blocked: batch delete in progress", level: .warning, category: .queue)
            return
        }

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

        // Pre-ensure all unique destination folders once before sending.
        // This eliminates redundant listFiles network calls per item (the single
        // biggest bottleneck for batch sends to the same folder).
        let uniqueFolders = Set(items.map { $0.destinationFolder ?? defaultFolder })
        var ensuredFolders = Set<String>()

        for folder in uniqueFolders {
            do {
                DebugLogger.log(
                    "Pre-ensuring folder: /\(folder)/",
                    level: .info, category: .queue
                )
                try await deviceVM.ensureFolder(folder)
                ensuredFolders.insert(folder)
            } catch {
                DebugLogger.log(
                    "Failed to pre-ensure folder /\(folder)/: \(error.localizedDescription)",
                    level: .warning, category: .queue
                )
                // Not fatal — individual uploads will retry ensureFolder if needed
            }
        }

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
            let skipEnsure = ensuredFolders.contains(folder)
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
                        "Sending item \(index + 1)/\(items.count): \(item.filename) (\(data.count) bytes) -> /\(folder)/",
                        level: .info, category: .queue
                    )

                    // Time the upload for adaptive estimation (overhead + data transfer, no cooldown)
                    let uploadStart = ContinuousClock.now
                    try await deviceVM.upload(
                        data: data,
                        filename: item.filename,
                        toFolder: folder,
                        skipEnsureFolder: skipEnsure
                    )
                    let uploadDuration = uploadStart.duration(to: .now)
                    let durationSeconds = Double(uploadDuration.components.seconds)
                                        + Double(uploadDuration.components.attoseconds) / 1e18

                    // Record transfer performance for improving future estimates
                    TransferStatsTracker.recordTransfer(bytes: item.fileSize, duration: durationSeconds)

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

            // Adaptive cooldown between items (skip after the last item).
            // Scales by file size: small EPUBs need minimal ESP32 recovery.
            if index < items.count - 1 && itemSent {
                try? await Task.sleep(for: Self.cooldown(forFileSize: item.fileSize))
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

    // MARK: - Transfer Time Estimation

    /// Threshold above which the large-queue warning is shown.
    static let largeQueueThreshold = 10

    /// Estimate total transfer time for a batch of queue items.
    ///
    /// Decomposes per-item time into three components:
    /// 1. **Overhead** — fixed cost per upload (HTTP setup, ESP32 processing).
    ///    Learned from real transfers via EMA, falls back to 1.5s.
    /// 2. **Data transfer** — `fileSize / rate`. Rate is learned via EMA,
    ///    falls back to 150 KB/s.
    /// 3. **Cooldown** — adaptive pause between items based on file size
    ///    (0.3s / 0.8s / 1.5s).
    ///
    /// A small constant is added for the one-time folder pre-ensure at batch start.
    static func estimateTransferTime(for items: [QueueItem]) -> (minutes: Int, seconds: Int, totalSeconds: Int) {
        let rate = TransferStatsTracker.effectiveTransferRate
        let overhead = TransferStatsTracker.effectiveOverhead

        // One-time cost: pre-ensure destination folders at batch start
        var total: Double = 1.0

        for (index, item) in items.enumerated() {
            // Per-item: overhead + data transfer
            total += overhead + (Double(item.fileSize) / rate)

            // Adaptive cooldown (not after the last item)
            if index < items.count - 1 {
                total += cooldownSeconds(forFileSize: item.fileSize)
            }
        }

        let totalInt = Int(total.rounded(.up))
        return (minutes: totalInt / 60, seconds: totalInt % 60, totalSeconds: totalInt)
    }

    /// Format the estimated transfer time as a human-readable string (e.g. "3 min 20 sec").
    static func formatTransferTime(for items: [QueueItem]) -> String {
        let est = estimateTransferTime(for: items)
        if est.minutes > 0 {
            return loc(.estimatedTimeMinSec, est.minutes, est.seconds)
        } else {
            return loc(.estimatedTimeSec, est.seconds)
        }
    }

    // MARK: - Send Single Item

    /// Enqueue an individual item for sending. If the send loop isn't running,
    /// it starts automatically. If it is already running, the item is appended
    /// and will be sent after the current item finishes.
    func enqueueSend(
        _ item: QueueItem,
        deviceVM: DeviceViewModel,
        settings: DeviceSettings,
        modelContext: ModelContext
    ) {
        guard !pendingSendIDs.contains(item.id) else { return }
        pendingSendIDs.append(item.id)

        // Start the send loop if it isn't running
        guard !isSendingSingle else { return }
        Task {
            await processSendQueue(deviceVM: deviceVM, settings: settings, modelContext: modelContext)
        }
    }

    /// Sequential loop that processes `pendingSendIDs` one at a time.
    /// New items can be appended while the loop is running.
    private func processSendQueue(
        deviceVM: DeviceViewModel,
        settings: DeviceSettings,
        modelContext: ModelContext
    ) async {
        guard !isSendingSingle else { return }
        isSendingSingle = true

        while !pendingSendIDs.isEmpty {
            let itemID = pendingSendIDs[0]

            // Fetch the QueueItem from SwiftData (it may have been removed)
            let descriptor = FetchDescriptor<QueueItem>(
                predicate: #Predicate<QueueItem> { $0.id == itemID }
            )
            guard let item = try? modelContext.fetch(descriptor).first else {
                pendingSendIDs.removeFirst()
                continue
            }

            let folder = item.destinationFolder ?? settings.convertFolder
            var sent = false

            do {
                let data = try Data(contentsOf: item.fileURL)

                DebugLogger.log(
                    "Single send: \(item.filename) (\(data.count) bytes) -> /\(folder)/",
                    level: .info, category: .queue
                )

                try await deviceVM.upload(
                    data: data,
                    filename: item.filename,
                    toFolder: folder
                )

                sent = true

                // Update linked Article status
                updateArticleStatus(articleID: item.articleID, to: .sent, modelContext: modelContext)

                // Update linked RSSArticle status
                if let rssID = item.rssArticleID {
                    updateRSSArticleStatus(rssArticleID: rssID, to: .sent, modelContext: modelContext)
                }

                // Delete file + record
                try? FileManager.default.removeItem(at: item.fileURL)
                modelContext.delete(item)

                // Log activity
                let event = ActivityEvent(
                    category: .queue,
                    action: .queueSend,
                    status: .success,
                    detail: loc(.sentSingleItem, item.filename)
                )
                modelContext.insert(event)

                DebugLogger.log(
                    "Single send complete: \(item.filename)",
                    level: .info, category: .queue
                )
            } catch {
                DebugLogger.log(
                    "Single send failed: \(item.filename) — \(error.localizedDescription)",
                    level: .error, category: .queue
                )
                errorMessage = loc(.failedToSendSingleItem, item.filename, error.localizedDescription)
            }

            pendingSendIDs.removeFirst()

            // Adaptive cooldown between items (only if more items pending)
            if sent && !pendingSendIDs.isEmpty {
                try? await Task.sleep(for: Self.cooldown(forFileSize: item.fileSize))
            }
        }

        isSendingSingle = false
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
