import Foundation
import ZIPFoundation

/// Builds EPUB 2.0 archives entirely in memory.
/// The output is a `Data` object containing the complete EPUB ZIP file.
struct EPUBBuilder {
    
    /// Metadata for the EPUB document.
    struct Metadata {
        let title: String
        let author: String
        let language: String
        let sourceURL: URL
        let description: String
        
        var publisher: String {
            sourceURL.host ?? "Unknown"
        }
        
        var date: String {
            ISO8601DateFormatter.shortDate.string(from: Date())
        }
    }
    
    /// Build an EPUB 2.0 from sanitized XHTML body content and metadata.
    ///
    /// Long content is automatically split into multiple chapters at `<h2>` headings
    /// or by paragraph count to reduce per-file size and improve e-reader performance.
    ///
    /// - Parameters:
    ///   - body: Sanitized XHTML body content (inner HTML, not a complete document).
    ///   - metadata: Article metadata.
    /// - Returns: EPUB file as in-memory Data.
    /// - Throws: If ZIP archive operations fail.
    static func build(body: String, metadata: Metadata) throws -> Data {
        let chapters = try ChapterSplitter.split(body: body, articleTitle: metadata.title)
        return try build(chapters: chapters, metadata: metadata)
    }
    
    /// Build an EPUB 2.0 from pre-split chapters and metadata.
    /// - Parameters:
    ///   - chapters: Array of chapters (at least one).
    ///   - metadata: Article metadata.
    /// - Returns: EPUB file as in-memory Data.
    /// - Throws: If ZIP archive operations fail.
    static func build(chapters: [Chapter], metadata: Metadata) throws -> Data {
        guard !chapters.isEmpty else {
            throw EPUBError.contentTooShort
        }
        
        let uuid = UUID().uuidString
        let escapedTitle = metadata.title.xmlEscaped
        let escapedAuthor = metadata.author.xmlEscaped
        let escapedDescription = metadata.description.xmlEscaped
        
        // Create in-memory ZIP archive
        guard let archive = Archive(accessMode: .create) else {
            throw EPUBError.archiveCreationFailed
        }
        
        // 1. mimetype — MUST be first entry, MUST be uncompressed (STORE)
        let mimetypeData = Data(EPUBTemplates.mimetype.utf8)
        try archive.addEntry(
            with: "mimetype",
            type: .file,
            uncompressedSize: UInt32(Int64(mimetypeData.count)),
            compressionMethod: .none,
            provider: { position, size in
                mimetypeData.subdata(in: position..<(position + size))
            }
        )
        
        // 2. META-INF/container.xml
        try addCompressedEntry(
            to: archive,
            path: "META-INF/container.xml",
            content: EPUBTemplates.containerXML
        )
        
        // Single chapter vs multi-chapter
        if chapters.count == 1 {
            // Use the original single-chapter templates for backward compatibility
            let opf = EPUBTemplates.contentOPF(
                uuid: uuid,
                title: escapedTitle,
                author: escapedAuthor,
                language: metadata.language,
                date: metadata.date,
                publisher: metadata.publisher.xmlEscaped,
                description: escapedDescription
            )
            try addCompressedEntry(to: archive, path: "OEBPS/content.opf", content: opf)
            
            let ncx = EPUBTemplates.tocNCX(uuid: uuid, title: escapedTitle)
            try addCompressedEntry(to: archive, path: "OEBPS/toc.ncx", content: ncx)
            
            let xhtml = EPUBTemplates.contentXHTML(
                title: escapedTitle,
                body: chapters[0].bodyHTML,
                language: metadata.language
            )
            try addCompressedEntry(to: archive, path: "OEBPS/content.xhtml", content: xhtml)
        } else {
            // Multi-chapter: generate OPF, NCX, and chapter XHTML files
            let opf = EPUBTemplates.contentOPF(
                uuid: uuid,
                title: escapedTitle,
                author: escapedAuthor,
                language: metadata.language,
                date: metadata.date,
                publisher: metadata.publisher.xmlEscaped,
                description: escapedDescription,
                chapterCount: chapters.count
            )
            try addCompressedEntry(to: archive, path: "OEBPS/content.opf", content: opf)
            
            let ncx = EPUBTemplates.tocNCX(uuid: uuid, title: escapedTitle, chapters: chapters)
            try addCompressedEntry(to: archive, path: "OEBPS/toc.ncx", content: ncx)
            
            // Add each chapter as a separate XHTML file
            for chapter in chapters {
                let xhtml = EPUBTemplates.chapterXHTML(
                    title: chapter.title.xmlEscaped,
                    body: chapter.bodyHTML,
                    language: metadata.language
                )
                try addCompressedEntry(
                    to: archive,
                    path: "OEBPS/chapter-\(chapter.index).xhtml",
                    content: xhtml
                )
            }
        }
        
        // Extract the archive data
        guard let data = archive.data else {
            throw EPUBError.archiveDataExtractionFailed
        }
        
        return data
    }
    
    /// Adds a UTF-8 text entry to the archive with DEFLATE compression.
    private static func addCompressedEntry(to archive: Archive, path: String, content: String) throws {
        let data = Data(content.utf8)
        try archive.addEntry(
            with: path,
            type: .file,
            uncompressedSize: UInt32(Int64(data.count)),
            compressionMethod: .deflate,
            provider: { position, size in
                data.subdata(in: position..<(position + size))
            }
        )
    }
}

/// Errors specific to EPUB generation.
enum EPUBError: LocalizedError {
    case archiveCreationFailed
    case archiveDataExtractionFailed
    case contentTooShort
    case invalidHTML
    
    var errorDescription: String? {
        switch self {
        case .archiveCreationFailed:
            return "Failed to create EPUB archive."
        case .archiveDataExtractionFailed:
            return "Failed to extract EPUB data from archive."
        case .contentTooShort:
            return "The extracted article content is too short. The page may not contain readable content."
        case .invalidHTML:
            return "The page HTML could not be parsed."
        }
    }
}
