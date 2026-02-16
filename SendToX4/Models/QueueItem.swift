import Foundation
import SwiftData

/// Persisted record of an EPUB file waiting to be sent to the device.
///
/// The EPUB binary is stored on disk at `Application Support/EPUBQueue/<id>.epub`.
/// The `QueueItem` record tracks metadata and the file path. When the item is sent
/// or cleared, both the record and the file are deleted.
@Model
final class QueueItem {
    var id: UUID
    var articleID: UUID
    var title: String
    var filename: String
    var filePath: String
    var fileSize: Int64
    var sourceURL: String
    var sourceDomain: String
    var queuedAt: Date

    /// Optional override for the device destination folder.
    /// When `nil`, the queue sender uses `settings.convertFolder` (the default).
    /// RSS feed articles set this to `"feed/<domain>"` so they are organized
    /// by source on the device.
    var destinationFolder: String?

    init(
        articleID: UUID,
        title: String,
        filename: String,
        filePath: String,
        fileSize: Int64,
        sourceURL: String,
        sourceDomain: String,
        destinationFolder: String? = nil
    ) {
        self.id = UUID()
        self.articleID = articleID
        self.title = title
        self.filename = filename
        self.filePath = filePath
        self.fileSize = Int64(fileSize)
        self.sourceURL = sourceURL
        self.sourceDomain = sourceDomain
        self.queuedAt = Date()
        self.destinationFolder = destinationFolder
    }

    /// Formatted file size for display (e.g., "1.2 MB").
    var formattedSize: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: fileSize)
    }

    /// Absolute URL to the EPUB file on disk.
    var fileURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent(filePath)
    }
}
