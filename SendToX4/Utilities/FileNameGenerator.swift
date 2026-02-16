import Foundation

/// Generates safe, descriptive filenames for EPUB files.
enum FileNameGenerator {
    
    /// Generate an EPUB filename in the format: "Title - Author - domain - YYYY-MM-DD.epub"
    static func generate(title: String, author: String?, url: URL) -> String {
        let cleanTitle = sanitizeComponent(title, maxLength: 60)
        let domain = url.host ?? "unknown"
        let dateStr = ISO8601DateFormatter.shortDate.string(from: Date())
        
        var components = [cleanTitle]
        if let author = author, !author.isEmpty {
            components.append(sanitizeComponent(author, maxLength: 30))
        }
        components.append(domain)
        components.append(dateStr)
        
        return components.joined(separator: " - ") + ".epub"
    }
    
    /// Remove filesystem-unsafe characters and trim whitespace.
    private static func sanitizeComponent(_ input: String, maxLength: Int) -> String {
        let unsafe = CharacterSet(charactersIn: "/\\:*?\"<>|")
        let cleaned = input
            .components(separatedBy: unsafe)
            .joined(separator: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        if cleaned.count > maxLength {
            return String(cleaned.prefix(maxLength)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return cleaned.isEmpty ? loc(.untitled) : cleaned
    }
}

extension ISO8601DateFormatter {
    /// Formatter that produces "YYYY-MM-DD" strings.
    static let shortDate: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate, .withDashSeparatorInDate]
        return formatter
    }()
}
