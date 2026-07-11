import Foundation
import SwiftSoup

/// Options controlling sanitization behavior.
struct SanitizerOptions {
    /// Keep `<img>`/`<figure>` elements, resolving their URLs for download
    /// and rewriting `src` to EPUB-relative placeholder paths.
    var keepImages = false
}

/// A reference to an article image discovered during sanitization.
/// The element's `src` has been rewritten to `placeholderPath`; the actual
/// bytes are downloaded later by `ImageDownloader`.
struct ImageRef: Sendable, Equatable {
    /// Stable zero-based index in document order.
    let index: Int
    /// Fully resolved source URL (http/https only).
    let absoluteURL: URL
    /// Alt text (may be empty) used as a fallback when download fails.
    let alt: String

    /// EPUB-relative path the `<img src>` was rewritten to.
    var placeholderPath: String { "images/img-\(index).jpg" }
}

/// Sanitized body content plus any image references found.
struct SanitizedContent {
    let bodyHTML: String
    let images: [ImageRef]
}

/// Sanitizes HTML content for safe inclusion in EPUB documents.
/// Strips scripts, styles, forms, media elements, and interactive content.
/// Images are stripped by default and preserved when
/// `SanitizerOptions.keepImages` is set.
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

    /// Hard cap on preserved images per article (matches ImageLimits.default).
    private static let maxImageRefs = 20

    /// Largest srcset width candidate worth downloading (downscaled to
    /// 1200 px later anyway).
    private static let maxUsefulSrcsetWidth = 1600

    // MARK: - String-Based API

    /// Sanitize raw HTML string for EPUB inclusion (text-only).
    /// Returns clean XHTML-compatible body content.
    static func sanitize(_ html: String) throws -> String {
        let doc = try SwiftSoup.parse(html)
        guard let body = doc.body() else { return "" }
        _ = try sanitizeElement(body, in: doc, applyXMLOutput: false)
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
    /// - Parameter baseURI: Base URL string used to resolve relative image
    ///   URLs when `options.keepImages` is set.
    static func sanitizeToXHTML(
        _ html: String,
        baseURI: String = "",
        options: SanitizerOptions = SanitizerOptions()
    ) throws -> SanitizedContent {
        let doc = try SwiftSoup.parse(html, baseURI)
        guard let body = doc.body() else {
            return SanitizedContent(bodyHTML: "", images: [])
        }
        let images = try sanitizeElement(body, in: doc, options: options, applyXMLOutput: true)
        return SanitizedContent(bodyHTML: try body.html(), images: images)
    }

    // MARK: - Element-Based API (single parse)

    /// Sanitize an already-parsed element subtree in place and configure the
    /// owning document for XHTML output. After this call,
    /// `try root.html()` yields sanitized XHTML body content.
    ///
    /// Used by `ContentExtractor` to avoid re-parsing the same content.
    ///
    /// - Returns: Image references when `options.keepImages` is set (their
    ///   `src` attributes have been rewritten to placeholder paths).
    @discardableResult
    static func sanitizeElement(
        _ root: Element,
        in doc: Document,
        options: SanitizerOptions = SanitizerOptions(),
        applyXMLOutput: Bool = true
    ) throws -> [ImageRef] {
        // Remove unwanted elements entirely
        for tag in removeWithContent {
            try root.select(tag).remove()
        }

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

        // Handle images (after clutter removal so widget images don't count)
        let images = try processImages(in: root, options: options)

        // Strip all attributes except href on anchors and src/alt on
        // preserved images
        let allElements = try root.select("*")
        for element in allElements {
            guard let attrs = element.getAttributes() else { continue }
            let tag = element.tagName()
            var keysToRemove: [String] = []
            for attr in attrs {
                let key = attr.getKey()
                if tag == "a" && key == "href" {
                    continue
                }
                if options.keepImages && tag == "img" && (key == "src" || key == "alt") {
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

        return images
    }

    // MARK: - Image Handling

    /// Strips images (default) or collects and rewrites them (keepImages).
    private static func processImages(
        in root: Element,
        options: SanitizerOptions
    ) throws -> [ImageRef] {
        guard options.keepImages else {
            // Text-only EPUB
            try root.select("img").remove()
            try root.select("picture").remove()
            try root.select("figure").remove()
            return []
        }

        // Collapse <picture> to its <img> (drop <source> variants)
        for picture in try root.select("picture") {
            if let img = try picture.select("img").first() {
                try picture.replaceWith(img)
            } else {
                try picture.remove()
            }
        }

        var refs: [ImageRef] = []
        for img in try root.select("img") {
            guard refs.count < maxImageRefs else {
                try img.remove() // over the cap — degrade gracefully
                continue
            }

            guard let url = try resolveImageURL(of: img) else {
                try img.remove() // data URI, tracking pixel, or unresolvable
                continue
            }

            let alt = (try? img.attr("alt")) ?? ""
            let ref = ImageRef(index: refs.count, absoluteURL: url, alt: alt)
            try img.attr("src", ref.placeholderPath)
            refs.append(ref)
        }

        return refs
    }

    /// Resolves an `<img>`'s best source URL, or nil when the image should
    /// be dropped (data URI, tracking pixel, non-HTTP scheme).
    private static func resolveImageURL(of img: Element) throws -> URL? {
        // Tracking pixels declare tiny explicit dimensions
        if let w = Int(try img.attr("width")), w <= 2 { return nil }
        if let h = Int(try img.attr("height")), h <= 2 { return nil }

        // Prefer the resolved src
        let absSrc = try img.attr("abs:src")
        if let url = validatedImageURL(absSrc) {
            return url
        }

        // Fall back to the largest useful srcset candidate
        let srcset = try img.attr("srcset")
        if !srcset.isEmpty {
            let base = URL(string: img.getBaseUri())
            if let candidate = bestSrcsetCandidate(srcset, relativeTo: base) {
                return candidate
            }
        }

        return nil
    }

    /// Validates a URL string as an http(s) image source.
    private static func validatedImageURL(_ string: String) -> URL? {
        guard !string.isEmpty,
              let url = URL(string: string),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return nil
        }
        return url
    }

    /// Picks the largest srcset candidate not exceeding `maxUsefulSrcsetWidth`
    /// (or the smallest available when all exceed it).
    private static func bestSrcsetCandidate(_ srcset: String, relativeTo base: URL?) -> URL? {
        var best: (url: URL, width: Int)?
        var smallest: (url: URL, width: Int)?

        for entry in srcset.split(separator: ",") {
            let parts = entry.trimmingCharacters(in: .whitespacesAndNewlines)
                .split(separator: " ", omittingEmptySubsequences: true)
            guard let urlPart = parts.first else { continue }

            var width = Int.max
            if parts.count > 1, parts[1].hasSuffix("w"),
               let value = Int(parts[1].dropLast()) {
                width = value
            }

            guard let resolved = URL(string: String(urlPart), relativeTo: base)?.absoluteURL,
                  let scheme = resolved.scheme?.lowercased(),
                  scheme == "http" || scheme == "https" else {
                continue
            }

            if smallest == nil || width < smallest!.width {
                smallest = (resolved, width)
            }
            if width <= maxUsefulSrcsetWidth {
                if best == nil || width > best!.width {
                    best = (resolved, width)
                }
            }
        }

        return best?.url ?? smallest?.url
    }

    /// Configure a document to serialize as XHTML.
    private static func applyXMLOutputSettings(to doc: Document) {
        doc.outputSettings()
            .syntax(syntax: OutputSettings.Syntax.xml)
            .escapeMode(Entities.EscapeMode.xhtml)
            .charset(String.Encoding.utf8)
    }
}
