import Foundation

/// Extracts tweet and X Article content via the fxtwitter API.
/// Bypasses X/Twitter's JS-only SPA, avoiding WKWebView entitlement issues on iOS 26+.
enum TwitterExtractor {

    /// Hosts that this extractor can handle.
    private static let supportedHosts: Set<String> = [
        "x.com", "www.x.com",
        "twitter.com", "www.twitter.com",
        "mobile.twitter.com"
    ]

    /// Check whether a URL is an X/Twitter status link.
    static func canHandle(url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        guard supportedHosts.contains(host) else { return false }
        // Must match /{user}/status/{id} pattern
        let parts = url.pathComponents.filter { $0 != "/" }
        return parts.count >= 3 && parts[1] == "status"
    }

    /// Extract content from an X/Twitter URL via the fxtwitter API.
    /// Returns nil if the API call fails or produces no usable content.
    static func extract(from url: URL) async throws -> ExtractedContent? {
        guard let apiURL = buildAPIURL(from: url) else { return nil }

        let (data, response) = try await URLSession.shared.data(from: apiURL)

        guard let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode) else {
            return nil
        }

        return try parseResponse(data: data)
    }

    // MARK: - URL Building

    /// Rewrite an x.com/twitter.com status URL to api.fxtwitter.com.
    private static func buildAPIURL(from url: URL) -> URL? {
        let parts = url.pathComponents.filter { $0 != "/" }
        // parts[0] = username, parts[1] = "status", parts[2] = tweetID
        guard parts.count >= 3, parts[1] == "status" else { return nil }
        let username = parts[0]
        let tweetID = parts[2]
        return URL(string: "https://api.fxtwitter.com/\(username)/status/\(tweetID)")
    }

    // MARK: - JSON Parsing

    private static func parseResponse(data: Data) throws -> ExtractedContent? {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tweet = root["tweet"] as? [String: Any] else {
            return nil
        }

        let author = (tweet["author"] as? [String: Any])
        let authorName = author?["name"] as? String
        let screenName = author?["screen_name"] as? String
        let lang = tweet["lang"] as? String

        // Check for X Article (long-form content)
        if let article = tweet["article"] as? [String: Any] {
            return parseArticle(
                article,
                authorName: authorName,
                screenName: screenName,
                lang: lang
            )
        }

        // Regular tweet
        return parseTweet(
            tweet,
            authorName: authorName,
            screenName: screenName,
            lang: lang
        )
    }

    // MARK: - Article Parsing

    private static func parseArticle(
        _ article: [String: Any],
        authorName: String?,
        screenName: String?,
        lang: String?
    ) -> ExtractedContent? {
        let title = article["title"] as? String ?? "Untitled"
        let previewText = article["preview_text"] as? String ?? ""

        guard let content = article["content"] as? [String: Any],
              let blocks = content["blocks"] as? [[String: Any]] else {
            return nil
        }

        let bodyHTML = renderBlocks(blocks)

        // Require meaningful content
        let plainText = bodyHTML.replacingOccurrences(
            of: "<[^>]+>",
            with: "",
            options: .regularExpression
        )
        guard plainText.count >= 200 else { return nil }

        return ExtractedContent(
            title: title,
            author: authorName,
            description: previewText,
            language: resolvedLanguage(lang),
            bodyHTML: bodyHTML
        )
    }

    // MARK: - Tweet Parsing

    private static func parseTweet(
        _ tweet: [String: Any],
        authorName: String?,
        screenName: String?,
        lang: String?
    ) -> ExtractedContent? {
        // Use raw_text if available, otherwise text
        let text: String
        if let rawText = tweet["raw_text"] as? [String: Any],
           let rawStr = rawText["text"] as? String, !rawStr.isEmpty {
            text = rawStr
        } else if let tweetText = tweet["text"] as? String, !tweetText.isEmpty {
            text = tweetText
        } else {
            return nil
        }

        // Skip tweets that are just a URL (like article links with no body text)
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://"),
           !trimmed.contains(" ") {
            return nil
        }

        let handle = screenName.map { "@\($0)" } ?? "X"
        let title = "\(authorName ?? handle) on X"

        // Build XHTML body from tweet text
        let paragraphs = text
            .components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .map { "<p>\($0.xmlEscaped)</p>" }

        let bodyHTML = paragraphs.joined(separator: "\n")
        guard !bodyHTML.isEmpty else { return nil }

        return ExtractedContent(
            title: title,
            author: authorName,
            description: String(text.prefix(200)),
            language: resolvedLanguage(lang),
            bodyHTML: bodyHTML
        )
    }

    // MARK: - Block Rendering (X Articles)

    /// Convert Draft.js-style content blocks into XHTML.
    private static func renderBlocks(_ blocks: [[String: Any]]) -> String {
        var html = ""
        var currentListType: String? = nil  // "ul" or "ol"

        for block in blocks {
            let type = block["type"] as? String ?? "unstyled"
            let text = block["text"] as? String ?? ""
            let inlineStyles = block["inlineStyleRanges"] as? [[String: Any]] ?? []

            // Handle list grouping
            let isListItem = type == "unordered-list-item" || type == "ordered-list-item"
            let neededList = isListItem
                ? (type == "unordered-list-item" ? "ul" : "ol")
                : nil

            // Close current list if switching type or leaving list context
            if currentListType != nil && currentListType != neededList {
                html += "</\(currentListType!)>\n"
                currentListType = nil
            }

            // Open new list if needed
            if let needed = neededList, currentListType == nil {
                html += "<\(needed)>\n"
                currentListType = needed
            }

            // Skip atomic blocks (embedded media — we're text-only)
            if type == "atomic" { continue }

            let styledText = applyInlineStyles(to: text, styles: inlineStyles)

            switch type {
            case "header-one":
                html += "<h1>\(styledText)</h1>\n"
            case "header-two":
                html += "<h2>\(styledText)</h2>\n"
            case "header-three":
                html += "<h3>\(styledText)</h3>\n"
            case "blockquote":
                html += "<blockquote><p>\(styledText)</p></blockquote>\n"
            case "unordered-list-item", "ordered-list-item":
                html += "<li>\(styledText)</li>\n"
            default:
                // "unstyled" and anything else → paragraph
                if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    html += "<p>\(styledText)</p>\n"
                }
            }
        }

        // Close any trailing list
        if let listType = currentListType {
            html += "</\(listType)>\n"
        }

        return html
    }

    /// Apply Bold/Italic inline style ranges to text, producing XHTML.
    private static func applyInlineStyles(
        to text: String,
        styles: [[String: Any]]
    ) -> String {
        guard !styles.isEmpty else { return text.xmlEscaped }

        // Build a character-level style map
        let chars = Array(text)
        var boldMap = [Bool](repeating: false, count: chars.count)
        var italicMap = [Bool](repeating: false, count: chars.count)

        for style in styles {
            guard let offset = style["offset"] as? Int,
                  let length = style["length"] as? Int,
                  let styleName = style["style"] as? String else { continue }

            let start = max(0, offset)
            let end = min(chars.count, offset + length)

            for i in start..<end {
                switch styleName {
                case "Bold": boldMap[i] = true
                case "Italic": italicMap[i] = true
                default: break
                }
            }
        }

        // Walk through characters and emit styled spans
        var result = ""
        var i = 0
        while i < chars.count {
            let bold = boldMap[i]
            let italic = italicMap[i]

            // Find the extent of this style run
            var j = i + 1
            while j < chars.count && boldMap[j] == bold && italicMap[j] == italic {
                j += 1
            }

            let segment = String(chars[i..<j]).xmlEscaped

            if bold && italic {
                result += "<strong><em>\(segment)</em></strong>"
            } else if bold {
                result += "<strong>\(segment)</strong>"
            } else if italic {
                result += "<em>\(segment)</em>"
            } else {
                result += segment
            }

            i = j
        }

        return result
    }

    // MARK: - Helpers

    private static func resolvedLanguage(_ lang: String?) -> String {
        guard let lang = lang, !lang.isEmpty, lang != "zxx" else { return "en" }
        return lang.components(separatedBy: "-").first ?? "en"
    }
}
