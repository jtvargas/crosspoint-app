import Foundation
import SwiftSoup

/// Sanitizes HTML content for safe inclusion in EPUB documents.
/// Strips scripts, styles, forms, media elements, images, and interactive content.
enum HTMLSanitizer {

    /// Elements to remove entirely (including their content).
    private static let removeWithContent: Set<String> = [
        "script", "style", "noscript", "iframe", "frame", "frameset",
        "object", "embed", "applet", "form", "input", "textarea",
        "select", "button", "video", "audio", "source", "canvas",
        "svg", "math", "template"
    ]

    /// Widget/clutter selectors removed by class or id substring match.
    /// Exposed for tests.
    static let clutterSelectors: [String] = [
        "[class*=share]", "[class*=social]", "[class*=comment]",
        "[class*=related]", "[class*=sidebar]", "[class*=advertisement]",
        "[class*=ad-]", "[class*=popup]", "[id*=comment]", "[id*=sidebar]"
    ]

    /// A clutter-selector match with at least this much own text is assumed
    /// to be real article content (e.g. `class="share-story-content"`) and
    /// is NOT removed.
    private static let clutterContentGuardTextLength = 500

    /// A clutter-selector match containing at least this many paragraphs is
    /// likewise protected from removal.
    private static let clutterContentGuardParagraphs = 3

    // MARK: - String-Based API

    /// Sanitize raw HTML string for EPUB inclusion.
    /// Returns clean XHTML-compatible body content.
    static func sanitize(_ html: String) throws -> String {
        let doc = try SwiftSoup.parse(html)
        guard let body = doc.body() else { return "" }
        try sanitizeElement(body, in: doc, applyXMLOutput: false)
        return try body.html()
    }

    /// Converts HTML to valid XHTML by ensuring proper tag closure and escaping.
    static func toXHTML(_ html: String) throws -> String {
        let doc = try SwiftSoup.parse(html)
        applyXMLOutputSettings(to: doc)
        guard let body = doc.body() else { return "" }
        return try body.html()
    }

    /// Sanitize + XHTML conversion in a single parse.
    static func sanitizeToXHTML(_ html: String) throws -> String {
        let doc = try SwiftSoup.parse(html)
        guard let body = doc.body() else { return "" }
        try sanitizeElement(body, in: doc, applyXMLOutput: true)
        return try body.html()
    }

    // MARK: - Element-Based API (single parse)

    /// Sanitize an already-parsed element subtree in place and configure the
    /// owning document for XHTML output. After this call,
    /// `try root.html()` yields sanitized XHTML body content.
    ///
    /// Used by `ContentExtractor` to avoid re-parsing the same content.
    static func sanitizeElement(
        _ root: Element,
        in doc: Document,
        applyXMLOutput: Bool = true
    ) throws {
        // Remove unwanted elements entirely
        for tag in removeWithContent {
            try root.select(tag).remove()
        }

        // Remove images (text-only EPUB)
        try root.select("img").remove()
        try root.select("picture").remove()
        try root.select("figure").remove()

        // Remove navigation and footer clutter
        try root.select("nav").remove()
        try root.select("footer").remove()
        try root.select("aside").remove()
        try root.select("header").remove()

        // Remove social/sharing widgets — but never remove an element that
        // looks like real article content (long text or many paragraphs);
        // substring class matches like "share-story-content" are false
        // positives.
        for selector in clutterSelectors {
            for element in try root.select(selector) {
                if element === root { continue }
                let paragraphCount = try element.select("p").size()
                if paragraphCount >= clutterContentGuardParagraphs { continue }
                let textLength = try element.text().count
                if textLength >= clutterContentGuardTextLength { continue }
                try element.remove()
            }
        }

        // Strip all attributes except href on anchors
        let allElements = try root.select("*")
        for element in allElements {
            guard let attrs = element.getAttributes() else { continue }
            var keysToRemove: [String] = []
            for attr in attrs {
                let key = attr.getKey()
                if element.tagName() == "a" && key == "href" {
                    continue
                }
                keysToRemove.append(key)
            }
            for key in keysToRemove {
                try element.removeAttr(key)
            }
        }

        // Convert links to plain text (e-readers handle links poorly)
        let links = try root.select("a")
        for link in links {
            try link.unwrap()
        }

        if applyXMLOutput {
            applyXMLOutputSettings(to: doc)
        }
    }

    /// Configure a document to serialize as XHTML.
    private static func applyXMLOutputSettings(to doc: Document) {
        doc.outputSettings()
            .syntax(syntax: OutputSettings.Syntax.xml)
            .escapeMode(Entities.EscapeMode.xhtml)
            .charset(String.Encoding.utf8)
    }
}
