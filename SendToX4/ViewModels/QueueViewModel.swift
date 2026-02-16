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
    private static func ensureQueueDirectory() throws {
        let url = queueDirectoryURL
        if !FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
    }

    // MARK: - Enqueue

    /// Write EPUB data to disk and create a QueueItem record.
    func enqueue(
        epubData: Data,
        filename: String,
        article: Article,
        modelContext: ModelContext
    ) {
        do {
            try Self.ensureQueueDirectory()

            let itemID = UUID()
            let relativePath = "EPUBQueue/\(itemID.uuidString).epub"
            let fileURL = Self.queueDirectoryURL.appendingPathComponent("\(itemID.uuidString).epub")

            try epubData.write(to: fileURL)

            let item = QueueItem(
                articleID: article.id,
                title: article.title.isEmpty ? "Untitled" : article.title,
                filename: filename,
                filePath: relativePath,
                fileSize: Int64(epubData.count),
                sourceURL: article.url,
                sourceDomain: article.sourceDomain
            )
            item.id = itemID
            modelContext.insert(item)
        } catch {
            errorMessage = "Failed to queue EPUB: \(error.localizedDescription)"
        }
    }

    // MARK: - Send All

    /// Send all queued items to the device sequentially.
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

        let folder = settings.convertFolder
        var sentFilenames: [String] = []
        var failCount = 0

        for (index, item) in items.enumerated() {
            sendProgress = (index + 1, items.count)
            currentFilename = item.filename

            do {
                let data = try Data(contentsOf: item.fileURL)
                try await deviceVM.upload(data: data, filename: item.filename, toFolder: folder)

                sentFilenames.append(item.filename)

                // Update linked Article status to .sent
                updateArticleStatus(articleID: item.articleID, to: .sent, modelContext: modelContext)

                // Delete file from disk
                try? FileManager.default.removeItem(at: item.fileURL)

                // Delete QueueItem record
                modelContext.delete(item)
            } catch {
                failCount += 1
                // Leave failed items in the queue for retry
                errorMessage = "Failed to send \(item.filename): \(error.localizedDescription)"
            }
        }

        // Log a single ActivityEvent summarizing the batch
        if !sentFilenames.isEmpty {
            let detail: String
            if sentFilenames.count == 1 {
                detail = "Sent \(sentFilenames[0])"
            } else {
                let names = sentFilenames.prefix(3).joined(separator: ", ")
                let suffix = sentFilenames.count > 3 ? " and \(sentFilenames.count - 3) more" : ""
                detail = "Sent \(sentFilenames.count) EPUBs: \(names)\(suffix)"
            }
            let event = ActivityEvent(
                category: .queue,
                action: .queueSend,
                status: failCount == 0 ? .success : .failed,
                detail: detail
            )
            modelContext.insert(event)
        }

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
}
