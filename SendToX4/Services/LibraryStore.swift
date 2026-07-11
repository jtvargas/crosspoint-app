import Foundation
import SwiftData

/// Persistent local library of converted EPUBs.
///
/// Unlike the send queue (whose files are deleted after upload), library
/// copies stick around so articles can be read in the in-app reader,
/// re-shared, or re-sent without a network round trip. Files live at
/// `Application Support/Library/<article.id>.epub` and are linked to the
/// `Article` record via `libraryFilePath`.
enum LibraryStore {

    /// Storage caps enforced by `enforceLimit` (oldest evicted first).
    static let maxTotalBytes: Int64 = 500 * 1024 * 1024
    static let maxItems = 300

    /// Overridable base directory (tests point this at a temp directory).
    static var baseDirectoryURL: URL = FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask).first!

    /// The library directory inside Application Support.
    static var directoryURL: URL {
        baseDirectoryURL.appendingPathComponent("Library")
    }

    /// Ensure the library directory exists on disk.
    static func ensureDirectory() throws {
        if !FileManager.default.fileExists(atPath: directoryURL.path) {
            try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        }
    }

    // MARK: - Save / Load / Delete

    /// Persist an EPUB for an article and link it on the record.
    @discardableResult
    static func save(epubData: Data, for article: Article) throws -> String {
        try ensureDirectory()
        let relativePath = "Library/\(article.id.uuidString).epub"
        let fileURL = directoryURL.appendingPathComponent("\(article.id.uuidString).epub")
        try epubData.write(to: fileURL)
        article.libraryFilePath = relativePath
        article.epubFileSize = Int64(epubData.count)
        return relativePath
    }

    /// The on-disk EPUB for an article, or nil when none exists.
    static func epubURL(for article: Article) -> URL? {
        guard article.libraryFilePath != nil else { return nil }
        let fileURL = directoryURL.appendingPathComponent("\(article.id.uuidString).epub")
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        return fileURL
    }

    /// Remove an article's library file (if any) and unlink the record.
    static func delete(for article: Article) {
        let fileURL = directoryURL.appendingPathComponent("\(article.id.uuidString).epub")
        try? FileManager.default.removeItem(at: fileURL)
        article.libraryFilePath = nil
        article.epubFileSize = nil
    }

    /// Delete every library file and unlink all articles.
    static func clearAll(modelContext: ModelContext) {
        if let contents = try? FileManager.default.contentsOfDirectory(
            at: directoryURL, includingPropertiesForKeys: nil
        ) {
            for fileURL in contents {
                try? FileManager.default.removeItem(at: fileURL)
            }
        }
        let descriptor = FetchDescriptor<Article>(
            predicate: #Predicate<Article> { $0.libraryFilePath != nil }
        )
        if let articles = try? modelContext.fetch(descriptor) {
            for article in articles {
                article.libraryFilePath = nil
                article.epubFileSize = nil
            }
        }
    }

    // MARK: - Limits

    /// Evict oldest library entries until the size/count caps are met.
    static func enforceLimit(modelContext: ModelContext) {
        let descriptor = FetchDescriptor<Article>(
            predicate: #Predicate<Article> { $0.libraryFilePath != nil },
            sortBy: [SortDescriptor(\.createdAt, order: .forward)]
        )
        guard let articles = try? modelContext.fetch(descriptor) else { return }

        var totalBytes = articles.reduce(Int64(0)) { $0 + ($1.epubFileSize ?? 0) }
        var count = articles.count

        for article in articles {
            guard totalBytes > maxTotalBytes || count > maxItems else { break }
            totalBytes -= article.epubFileSize ?? 0
            count -= 1
            delete(for: article)
            DebugLogger.log(
                "Library evicted oldest entry: \(article.title)",
                level: .info, category: .conversion
            )
        }
    }

    /// Total bytes currently stored in the library directory.
    static var totalBytes: Int64 {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: directoryURL, includingPropertiesForKeys: [.fileSizeKey]
        ) else {
            return 0
        }
        return contents.reduce(Int64(0)) { total, url in
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
            return total + Int64(size)
        }
    }

    /// Number of EPUBs currently stored in the library directory.
    static var itemCount: Int {
        (try? FileManager.default.contentsOfDirectory(
            at: directoryURL, includingPropertiesForKeys: nil
        ))?.count ?? 0
    }
}
