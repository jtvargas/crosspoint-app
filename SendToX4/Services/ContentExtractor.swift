import Foundation
import SwiftSoup

/// Extracted article content with metadata.
struct ExtractedContent {
    let title: String
    let author: String?
    let description: String
    let language: String
    let bodyHTML: String
}

/// Extracts article content from HTML using SwiftSoup heuristics.
/// This is the primary (fast) extraction method.
enum ContentExtractor {
    
    /// Minimum text length to consider extraction successful.
    private static let minimumContentLength = 400
    
    /// Extract article content from raw HTML.
    /// Returns nil if the extraction produces too little content (triggers fallback).
    static func extract(from html: String, url: URL) throws -> ExtractedContent? {
        let doc = try SwiftSoup.parse(html, url.absoluteString)
        
        // Extract metadata
        let title = try extractTitle(from: doc)
        let author = try extractAuthor(from: doc)
        let description = try extractDescription(from: doc)
        let language = try doc.select("html").first()?.attr("lang") ?? "en"
        
        // Extract article body
        guard let bodyHTML = try extractArticleBody(from: doc) else {
            return nil
        }
        
        // Sanitize the extracted HTML
        let sanitized = try HTMLSanitizer.sanitize(bodyHTML)
        
        // Validate content length
        let textContent = try SwiftSoup.parse(sanitized).text()
        guard textContent.count >= minimumContentLength else {
            return nil // Too short — trigger fallback to Readability.js
        }
        
        // Convert to XHTML
        let xhtml = try HTMLSanitizer.toXHTML(sanitized)
        
        return ExtractedContent(
            title: title,
            author: author,
            description: description,
            language: language.components(separatedBy: "-").first ?? "en",
            bodyHTML: xhtml
        )
    }
    
    // MARK: - Metadata Extraction
    
    private static func extractTitle(from doc: Document) throws -> String {
        // Priority: og:title > meta title > <title> > first <h1>
        if let ogTitle = try doc.select("meta[property=og:title]").first()?.attr("content"),
           !ogTitle.isEmpty {
            return ogTitle.condensed
        }
        if let metaTitle = try doc.select("meta[name=title]").first()?.attr("content"),
           !metaTitle.isEmpty {
            return metaTitle.condensed
        }
        let title = try doc.title()
        if !title.isEmpty {
            // Strip site name suffix (e.g., "Article Title | Site Name")
            let separators = [" | ", " - ", " — ", " :: ", " » "]
            for sep in separators {
                if let range = title.range(of: sep, options: .backwards) {
                    let candidate = String(title[..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
                    if candidate.count > 10 { return candidate }
                }
            }
            return title.condensed
        }
        if let h1 = try doc.select("h1").first()?.text(), !h1.isEmpty {
            return h1.condensed
        }
        return "Untitled"
    }
    
    private static func extractAuthor(from doc: Document) throws -> String? {
        let selectors = [
            "meta[name=author]",
            "meta[property=article:author]",
            "meta[property=og:article:author]",
            "[rel=author]",
            ".author",
            ".byline",
            "[itemprop=author]"
        ]
        for selector in selectors {
            if let element = try doc.select(selector).first() {
                let content = try element.attr("content")
                if !content.isEmpty { return content.condensed }
                let text = try element.text()
                if !text.isEmpty { return text.condensed }
            }
        }
        return nil
    }
    
    private static func extractDescription(from doc: Document) throws -> String {
        if let ogDesc = try doc.select("meta[property=og:description]").first()?.attr("content"),
           !ogDesc.isEmpty {
            return ogDesc.condensed
        }
        if let metaDesc = try doc.select("meta[name=description]").first()?.attr("content"),
           !metaDesc.isEmpty {
            return metaDesc.condensed
        }
        return ""
    }
    
    // MARK: - Article Body Extraction
    
    /// Heuristic article body extraction.
    /// Tries known article containers, then falls back to scoring elements by text density.
    private static func extractArticleBody(from doc: Document) throws -> String? {
        // Strategy 1: Look for known article containers
        let articleSelectors = [
            "article",
            "[role=main]",
            "main",
            ".post-content",
            ".article-content",
            ".article-body",
            ".entry-content",
            ".post-body",
            ".story-body",
            "#article-body",
            "#article-content",
            ".content-body"
        ]
        
        for selector in articleSelectors {
            if let element = try doc.select(selector).first() {
                let html = try element.html()
                let text = try element.text()
                if text.count >= minimumContentLength {
                    return html
                }
            }
        }
        
        // Strategy 2: Score elements by text density
        guard let body = doc.body() else { return nil }
        
        var bestElement: Element?
        var bestScore = 0
        
        let candidates = try body.select("div, section, td")
        for candidate in candidates {
            let text = try candidate.text()
            let paragraphs = try candidate.select("p").size()
            
            // Score: text length + paragraph count bonus
            let score = text.count + (paragraphs * 100)
            
            // Must have meaningful content and some structure
            if score > bestScore && text.count >= minimumContentLength && paragraphs >= 2 {
                bestScore = score
                bestElement = candidate
            }
        }
        
        if let best = bestElement {
            return try best.html()
        }
        
        // Strategy 3: Just use body content
        let bodyText = try body.text()
        if bodyText.count >= minimumContentLength {
            return try body.html()
        }
        
        return nil
    }
}
