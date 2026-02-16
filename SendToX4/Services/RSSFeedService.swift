import Foundation

// MARK: - RSSFeedService

/// Stateless service for fetching, parsing, and discovering RSS/Atom feeds.
///
/// Supports both RSS 2.0 (`<channel>/<item>`) and Atom (`<feed>/<entry>`) formats.
/// Uses Foundation's `XMLParser` — no external dependencies.
nonisolated enum RSSFeedService {

    // MARK: - Output Types

    /// Parsed feed metadata and items.
    struct ParsedFeed: Sendable {
        let title: String
        let link: String
        let items: [ParsedItem]
    }

    /// A single parsed feed item.
    struct ParsedItem: Sendable {
        let title: String
        let link: String
        let author: String?
        let summary: String?
        let publishedDate: Date?
    }

    /// Errors specific to RSS feed operations.
    enum RSSError: LocalizedError, Sendable {
        case invalidURL
        case fetchFailed(String)
        case parseFailed
        case noFeedFound
        case notAFeed

        var errorDescription: String? {
            switch self {
            case .invalidURL: return "Invalid feed URL."
            case .fetchFailed(let reason): return "Failed to fetch feed: \(reason)"
            case .parseFailed: return "Could not parse the feed XML."
            case .noFeedFound: return "No RSS or Atom feed found on this page."
            case .notAFeed: return "The URL does not point to a valid RSS or Atom feed."
            }
        }
    }

    // MARK: - Public API

    /// Fetch and parse an RSS/Atom feed from the given URL.
    ///
    /// - Parameter url: Direct URL to the RSS/Atom XML feed.
    /// - Returns: Parsed feed with title, link, and items.
    static func fetch(url: URL) async throws -> ParsedFeed {
        let (data, response) = try await urlSession.data(from: url)

        if let httpResponse = response as? HTTPURLResponse,
           !(200...299).contains(httpResponse.statusCode) {
            throw RSSError.fetchFailed("HTTP \(httpResponse.statusCode)")
        }

        return try parse(data: data)
    }

    /// Validate that a URL points to a valid RSS/Atom feed.
    ///
    /// Fetches the URL and attempts to parse it. If successful, returns the feed.
    static func validate(url: URL) async throws -> ParsedFeed {
        let feed = try await fetch(url: url)
        guard !feed.items.isEmpty || !feed.title.isEmpty else {
            throw RSSError.notAFeed
        }
        return feed
    }

    /// Auto-discover the RSS/Atom feed URL from a website HTML page.
    ///
    /// Looks for `<link rel="alternate" type="application/rss+xml">` or
    /// `type="application/atom+xml"` in the HTML `<head>`.
    ///
    /// - Parameter websiteURL: URL of a regular HTML page.
    /// - Returns: The discovered feed URL, or `nil` if none found.
    static func discoverFeed(from websiteURL: URL) async throws -> URL? {
        let (data, _) = try await urlSession.data(from: websiteURL)

        guard let html = String(data: data, encoding: .utf8) else {
            return nil
        }

        // Look for <link rel="alternate" type="application/rss+xml" href="...">
        // and <link rel="alternate" type="application/atom+xml" href="...">
        let patterns = [
            "application/rss+xml",
            "application/atom+xml",
        ]

        for pattern in patterns {
            if let feedURL = extractFeedLink(from: html, type: pattern, baseURL: websiteURL) {
                return feedURL
            }
        }

        // Try common feed URL patterns as fallback
        let commonPaths = ["/feed", "/feed/", "/rss", "/rss.xml", "/atom.xml", "/feed.xml", "/index.xml"]
        for path in commonPaths {
            guard let candidateURL = URL(string: path, relativeTo: websiteURL)?.absoluteURL else {
                continue
            }
            // Quick HEAD check to see if it exists
            var request = URLRequest(url: candidateURL)
            request.httpMethod = "HEAD"
            request.timeoutInterval = 5
            if let (_, response) = try? await urlSession.data(for: request),
               let http = response as? HTTPURLResponse,
               (200...299).contains(http.statusCode) {
                // Validate it's actually a feed
                if let _ = try? await validate(url: candidateURL) {
                    return candidateURL
                }
            }
        }

        return nil
    }

    // MARK: - Private: URLSession

    private static var urlSession: URLSession {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 30
        return URLSession(configuration: config)
    }

    // MARK: - Private: Feed Link Extraction

    /// Extract a feed link from HTML by searching for <link> tags with the given type.
    private static func extractFeedLink(from html: String, type: String, baseURL: URL) -> URL? {
        // Simple regex to find <link ... type="application/rss+xml" ... href="..." ...>
        // We need to handle attributes in any order.
        let linkPattern = #"<link\s[^>]*>"#
        guard let linkRegex = try? NSRegularExpression(pattern: linkPattern, options: .caseInsensitive) else {
            return nil
        }

        let range = NSRange(html.startIndex..., in: html)
        let matches = linkRegex.matches(in: html, range: range)

        for match in matches {
            guard let matchRange = Range(match.range, in: html) else { continue }
            let tag = String(html[matchRange])

            // Check if this link has the right type
            guard tag.lowercased().contains(type.lowercased()) else { continue }

            // Check if it has rel="alternate"
            guard tag.lowercased().contains("alternate") else { continue }

            // Extract href value
            if let href = extractAttribute("href", from: tag) {
                if let feedURL = URL(string: href, relativeTo: baseURL) {
                    return feedURL.absoluteURL
                }
            }
        }

        return nil
    }

    /// Extract an attribute value from an HTML tag string.
    private static func extractAttribute(_ name: String, from tag: String) -> String? {
        // Match name="value" or name='value'
        let pattern = #"\b"# + NSRegularExpression.escapedPattern(for: name) + #"\s*=\s*["']([^"']*)["']"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
            return nil
        }
        let range = NSRange(tag.startIndex..., in: tag)
        guard let match = regex.firstMatch(in: tag, range: range),
              let valueRange = Range(match.range(at: 1), in: tag) else {
            return nil
        }
        return String(tag[valueRange])
    }

    // MARK: - Private: XML Parsing

    /// Parse RSS/Atom XML data into a `ParsedFeed`.
    private static func parse(data: Data) throws -> ParsedFeed {
        let delegate = RSSXMLParserDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.shouldProcessNamespaces = false
        parser.shouldReportNamespacePrefixes = false

        guard parser.parse(), delegate.didFindFeed else {
            throw RSSError.parseFailed
        }

        return ParsedFeed(
            title: delegate.feedTitle.trimmingCharacters(in: .whitespacesAndNewlines),
            link: delegate.feedLink.trimmingCharacters(in: .whitespacesAndNewlines),
            items: delegate.items
        )
    }
}

// MARK: - XML Parser Delegate

/// Internal delegate that handles both RSS 2.0 and Atom feed formats.
private final class RSSXMLParserDelegate: NSObject, XMLParserDelegate, @unchecked Sendable {

    // Feed-level data
    var feedTitle = ""
    var feedLink = ""
    var didFindFeed = false

    // Items
    var items: [RSSFeedService.ParsedItem] = []

    // Parser state
    private var currentElement = ""
    private var isInsideItem = false
    private var isInsideChannel = false
    private var isAtomFeed = false

    // Current item being built
    private var currentTitle = ""
    private var currentLink = ""
    private var currentAuthor = ""
    private var currentSummary = ""
    private var currentPubDate = ""

    // Character buffer
    private var characterBuffer = ""

    // MARK: - XMLParserDelegate

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName: String?,
        attributes: [String: String]
    ) {
        let name = elementName.lowercased()
        currentElement = name
        characterBuffer = ""

        switch name {
        case "rss":
            didFindFeed = true

        case "feed":
            // Atom feed
            didFindFeed = true
            isAtomFeed = true

        case "channel":
            isInsideChannel = true

        case "item":
            // RSS 2.0 item
            isInsideItem = true
            resetCurrentItem()

        case "entry":
            // Atom entry
            isInsideItem = true
            resetCurrentItem()

        case "link":
            if isAtomFeed {
                // Atom: <link href="..." rel="alternate" />
                let rel = attributes["rel"] ?? "alternate"
                let href = attributes["href"] ?? ""
                if isInsideItem {
                    if rel == "alternate" || currentLink.isEmpty {
                        currentLink = href
                    }
                } else {
                    if rel == "alternate" || feedLink.isEmpty {
                        feedLink = href
                    }
                }
            }

        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        characterBuffer += string
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName: String?
    ) {
        let name = elementName.lowercased()
        let content = characterBuffer.trimmingCharacters(in: .whitespacesAndNewlines)

        if isInsideItem {
            switch name {
            case "title":
                currentTitle = content
            case "link":
                if !isAtomFeed {
                    currentLink = content
                }
            case "author", "dc:creator":
                currentAuthor = content
            case "name":
                // Atom author name: <author><name>...</name></author>
                if currentAuthor.isEmpty {
                    currentAuthor = content
                }
            case "description", "summary", "content:encoded":
                if currentSummary.isEmpty || name == "summary" {
                    currentSummary = content
                }
            case "pubdate", "published", "updated", "dc:date":
                if currentPubDate.isEmpty {
                    currentPubDate = content
                }
            case "item", "entry":
                // Finalize the item
                let item = RSSFeedService.ParsedItem(
                    title: currentTitle,
                    link: currentLink,
                    author: currentAuthor.isEmpty ? nil : currentAuthor,
                    summary: stripHTML(currentSummary).isEmpty ? nil : stripHTML(currentSummary),
                    publishedDate: parseDate(currentPubDate)
                )
                items.append(item)
                isInsideItem = false
            default:
                break
            }
        } else {
            // Feed-level elements
            switch name {
            case "title":
                if feedTitle.isEmpty {
                    feedTitle = content
                }
            case "link":
                if !isAtomFeed && feedLink.isEmpty {
                    feedLink = content
                }
            case "channel":
                isInsideChannel = false
            default:
                break
            }
        }

        characterBuffer = ""
    }

    // MARK: - Helpers

    private func resetCurrentItem() {
        currentTitle = ""
        currentLink = ""
        currentAuthor = ""
        currentSummary = ""
        currentPubDate = ""
    }

    /// Strip HTML tags from a string for plain-text summary display.
    private func stripHTML(_ html: String) -> String {
        guard !html.isEmpty else { return "" }
        // Simple regex strip — handles most RSS description HTML
        let stripped = html
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&nbsp;", with: " ")
        return stripped.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Parse a date string from various RSS/Atom date formats.
    private func parseDate(_ string: String) -> Date? {
        guard !string.isEmpty else { return nil }

        // Try RFC 822 (RSS 2.0): "Mon, 02 Jan 2006 15:04:05 +0000"
        let rfc822 = DateFormatter()
        rfc822.locale = Locale(identifier: "en_US_POSIX")
        rfc822.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
        if let date = rfc822.date(from: string) { return date }

        // Try without day name
        rfc822.dateFormat = "dd MMM yyyy HH:mm:ss Z"
        if let date = rfc822.date(from: string) { return date }

        // Try ISO 8601 (Atom): "2006-01-02T15:04:05Z"
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        if let date = iso.date(from: string) { return date }

        // Try ISO 8601 with fractional seconds
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = iso.date(from: string) { return date }

        return nil
    }
}
