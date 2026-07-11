import Foundation
import SwiftData

/// Represents the current state of an article through the conversion pipeline.
enum ConversionStatus: String, Codable {
    case pending
    case fetching
    case extracting
    case building
    case sending
    case sent
    case savedLocally
    case failed
}

/// Persisted record of a web page conversion.
@Model
final class Article {
    var id: UUID
    var url: String
    var title: String
    var author: String?
    var sourceDomain: String
    var createdAt: Date
    var statusRaw: String  // Store ConversionStatus as raw String for SwiftData compatibility
    var errorMessage: String?

    // MARK: - Library (optional -> lightweight migration)

    /// Relative path of the persisted EPUB in the local library
    /// ("Library/<id>.epub"), or nil when no copy is kept.
    var libraryFilePath: String?

    /// Size in bytes of the persisted EPUB (for storage UI and eviction).
    var epubFileSize: Int64?

    /// Reading progress in the in-app reader (0...1 scroll fraction).
    var readingProgress: Double?
    
    var status: ConversionStatus {
        get { ConversionStatus(rawValue: statusRaw) ?? .pending }
        set { statusRaw = newValue.rawValue }
    }
    
    init(url: String, title: String = "", author: String? = nil, sourceDomain: String = "") {
        self.id = UUID()
        self.url = url
        self.title = title
        self.author = author
        self.sourceDomain = sourceDomain
        self.createdAt = Date()
        self.statusRaw = ConversionStatus.pending.rawValue
    }
}
