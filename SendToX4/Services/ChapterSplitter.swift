import Foundation
import SwiftSoup

/// A chapter within an EPUB document.
struct Chapter {
    /// Zero-based chapter index.
    let index: Int
    /// Chapter title (from <h2> text or "Part N").
    let title: String
    /// Sanitized XHTML body content for this chapter.
    let bodyHTML: String
}

/// Splits long HTML content into multiple chapters for EPUB generation.
/// This reduces per-file size and improves reading experience on e-readers.
enum ChapterSplitter {

    /// Minimum text length (in characters) before splitting is considered.
    /// Content shorter than this stays as a single chapter.
    private static let splitThreshold = 15_000

    /// Maximum number of paragraphs per chapter when splitting by paragraph count.
    private static let maxParagraphsPerChapter = 50

    /// Split HTML body content into chapters.
    ///
    /// Strategy:
    /// 1. If content is short (< splitThreshold chars), return a single chapter.
    /// 2. Try splitting at `<h2>` headings (natural section boundaries).
    /// 3. If no `<h2>` headings, split by paragraph count.
    ///
    /// The body is parsed exactly once; both split strategies work on the
    /// same DOM.
    ///
    /// - Parameters:
    ///   - body: Sanitized XHTML body content (inner HTML).
    ///   - articleTitle: The article title (used for the first chapter if splitting).
    /// - Returns: Array of chapters. Always contains at least one chapter.
    static func split(body: String, articleTitle: String) throws -> [Chapter] {
        let single = [Chapter(index: 0, title: articleTitle, bodyHTML: body)]

        let doc = try SwiftSoup.parseBodyFragment(body)
        guard let docBody = doc.body() else { return single }

        // Check if splitting is needed (DOM text, not regex tag-stripping)
        let textLength = try docBody.text().count
        guard textLength >= splitThreshold else { return single }

        // Try splitting at <h2> headings
        let h2Chapters = try splitAtHeadings(docBody: docBody, articleTitle: articleTitle)
        if h2Chapters.count > 1 {
            return h2Chapters
        }

        // Fallback: split by paragraph count
        let paragraphChapters = try splitByParagraphs(docBody: docBody, articleTitle: articleTitle)
        return paragraphChapters.count > 1 ? paragraphChapters : single
    }

    // MARK: - Split at <h2> Headings

    /// Splits content at `<h2>` boundaries. Content before the first `<h2>` becomes
    /// the first chapter (using the article title). Each `<h2>` starts a new chapter.
    ///
    /// When an `<h2>`'s text becomes the chapter title, the heading itself is
    /// omitted from the chapter body — the XHTML template already renders the
    /// title as the chapter's `<h1>`, so keeping it would duplicate the heading.
    private static func splitAtHeadings(docBody: Element, articleTitle: String) throws -> [Chapter] {
        let children = docBody.children()

        // Find all h2 positions
        var h2Indices: [Int] = []
        for i in 0..<children.size() {
            let child = children.get(i)
            if child.tagName().lowercased() == "h2" {
                h2Indices.append(i)
            }
        }

        guard h2Indices.count >= 2 else {
            // Not enough headings to split meaningfully
            return []
        }

        var chapters: [Chapter] = []
        var chapterIndex = 0

        // Content before first h2 (preamble)
        if h2Indices[0] > 0 {
            var preambleHTML = ""
            for i in 0..<h2Indices[0] {
                preambleHTML += try children.get(i).outerHtml() + "\n"
            }
            let trimmed = preambleHTML.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                chapters.append(Chapter(
                    index: chapterIndex,
                    title: articleTitle,
                    bodyHTML: trimmed
                ))
                chapterIndex += 1
            }
        }

        // Each h2 starts a new chapter
        for (pos, h2Index) in h2Indices.enumerated() {
            let h2Element = children.get(h2Index)
            let chapterTitle = try h2Element.text().trimmingCharacters(in: .whitespacesAndNewlines)
            let titleFromHeading = !chapterTitle.isEmpty
            let displayTitle = titleFromHeading ? chapterTitle : "Part \(chapterIndex + 1)"

            // Collect content from this h2 to the next h2 (or end)
            let endIndex = (pos + 1 < h2Indices.count) ? h2Indices[pos + 1] : children.size()

            var chapterHTML = ""
            // Only re-emit the h2 when its text did NOT become the chapter
            // title (the template renders the title as <h1> already).
            if !titleFromHeading {
                chapterHTML += try h2Element.outerHtml() + "\n"
            }
            for i in (h2Index + 1)..<endIndex {
                chapterHTML += try children.get(i).outerHtml() + "\n"
            }

            let trimmed = chapterHTML.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                chapters.append(Chapter(
                    index: chapterIndex,
                    title: displayTitle,
                    bodyHTML: trimmed
                ))
                chapterIndex += 1
            }
        }

        // If we ended up with just 1 chapter somehow, signal "no h2 split"
        guard chapters.count > 1 else { return [] }

        return chapters
    }

    // MARK: - Split by Paragraph Count

    /// Splits content into chapters of approximately `maxParagraphsPerChapter` paragraphs each.
    /// Groups top-level block elements from the already-parsed body.
    private static func splitByParagraphs(docBody: Element, articleTitle: String) throws -> [Chapter] {
        let children = docBody.children()
        let totalElements = children.size()

        guard totalElements > maxParagraphsPerChapter else {
            return []
        }

        var chapters: [Chapter] = []
        var currentHTML = ""
        var elementCount = 0
        var chapterIndex = 0

        for i in 0..<totalElements {
            let child = children.get(i)
            currentHTML += try child.outerHtml() + "\n"
            elementCount += 1

            // Split at the threshold, but try to avoid splitting mid-sentence
            // by looking for a natural break (end of a paragraph)
            let isBlockEnd = ["p", "div", "blockquote", "ul", "ol", "table"]
                .contains(child.tagName().lowercased())

            if elementCount >= maxParagraphsPerChapter && isBlockEnd {
                let trimmed = currentHTML.trimmingCharacters(in: .whitespacesAndNewlines)
                let title = chapterIndex == 0
                    ? articleTitle
                    : "\(articleTitle) \u{2014} Part \(chapterIndex + 1)"
                chapters.append(Chapter(
                    index: chapterIndex,
                    title: title,
                    bodyHTML: trimmed
                ))
                chapterIndex += 1
                currentHTML = ""
                elementCount = 0
            }
        }

        // Remaining content
        let trimmed = currentHTML.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            let title = chapterIndex == 0
                ? articleTitle
                : "\(articleTitle) \u{2014} Part \(chapterIndex + 1)"
            chapters.append(Chapter(
                index: chapterIndex,
                title: title,
                bodyHTML: trimmed
            ))
        }

        return chapters
    }
}
