import Foundation

/// Result of fetching a web page.
struct FetchedPage {
    let html: String
    let finalURL: URL
    let language: String
}

/// Fetches web page HTML via URLSession with optimized configuration.
enum WebPageFetcher {

    /// Shared URLSession with performance-optimized configuration.
    private static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        config.httpMaximumConnectionsPerHost = 4
        config.requestCachePolicy = .returnCacheDataElseLoad
        return URLSession(configuration: config)
    }()

    /// Maximum retry attempts after the initial request (transient failures only).
    private static let maxRetries = 2

    /// Backoff delays before retry attempts 1 and 2.
    private static let retryDelays: [Duration] = [.milliseconds(500), .milliseconds(1500)]

    /// Fetch the HTML content of a web page.
    /// Follows redirects automatically and captures the final URL.
    /// Transient failures (timeouts, connection drops, HTTP 5xx/429) are
    /// retried with a short backoff before surfacing an error.
    static func fetch(url: URL) async throws -> FetchedPage {
        var request = URLRequest(url: url)
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 26_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Mobile/15E148 Safari/604.1",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")

        var lastError: Error = FetchError.invalidResponse

        for attempt in 0...maxRetries {
            if attempt > 0 {
                try? await Task.sleep(for: retryDelays[attempt - 1])
                DebugLogger.log(
                    "Fetch retry \(attempt)/\(maxRetries): \(url.absoluteString)",
                    level: .warning, category: .conversion
                )
            }

            do {
                let (data, response) = try await session.data(for: request)

                guard let httpResponse = response as? HTTPURLResponse else {
                    throw FetchError.invalidResponse
                }

                guard (200...299).contains(httpResponse.statusCode) else {
                    let error = FetchError.httpError(statusCode: httpResponse.statusCode)
                    if isRetryableStatus(httpResponse.statusCode) && attempt < maxRetries {
                        lastError = error
                        continue
                    }
                    throw error
                }

                guard let html = decode(
                    data: data,
                    headerCharset: httpResponse.textEncodingName
                ) else {
                    throw FetchError.decodingFailed
                }

                let finalURL = httpResponse.url ?? url
                let language = extractLanguage(fromHTMLTag: html) ?? "en"

                return FetchedPage(html: html, finalURL: finalURL, language: language)
            } catch let urlError as URLError where isTransient(urlError) && attempt < maxRetries {
                lastError = urlError
                continue
            }
        }

        throw lastError
    }

    // MARK: - Retry Classification

    private static func isRetryableStatus(_ statusCode: Int) -> Bool {
        statusCode == 429 || (500...599).contains(statusCode)
    }

    private static func isTransient(_ error: URLError) -> Bool {
        switch error.code {
        case .timedOut, .networkConnectionLost, .cannotConnectToHost,
             .dnsLookupFailed, .notConnectedToInternet, .cannotFindHost:
            return true
        default:
            return false
        }
    }

    // MARK: - Decoding

    /// Decode page bytes into a String.
    ///
    /// Priority: HTTP header charset → UTF-8 → `<meta charset>` sniffed from
    /// the document head → Latin-1 last resort. Pure function for testability.
    static func decode(data: Data, headerCharset: String?) -> String? {
        if let name = headerCharset,
           let encoding = String.Encoding(ianaCharsetName: name),
           let html = String(data: data, encoding: encoding) {
            return html
        }

        if let html = String(data: data, encoding: .utf8) {
            return html
        }

        // The header lied or was missing and the bytes aren't UTF-8:
        // sniff a <meta charset> declaration from the first 2 KB (the
        // declaration itself is always ASCII).
        if let sniffed = sniffMetaCharset(in: data),
           let encoding = String.Encoding(ianaCharsetName: sniffed),
           let html = String(data: data, encoding: encoding) {
            return html
        }

        return String(data: data, encoding: .isoLatin1)
    }

    /// Scan the leading bytes for `<meta charset="...">` or
    /// `<meta http-equiv="Content-Type" content="...; charset=...">`.
    static func sniffMetaCharset(in data: Data) -> String? {
        let head = data.prefix(2048)
        // Lossy ASCII view is fine: charset declarations are pure ASCII.
        let text = String(decoding: head, as: UTF8.self).lowercased()
        guard let regex = try? NSRegularExpression(
            pattern: "charset\\s*=\\s*[\"']?\\s*([a-z0-9_\\-]+)"
        ) else {
            return nil
        }
        let nsText = text as NSString
        guard let match = regex.firstMatch(
            in: text, range: NSRange(location: 0, length: nsText.length)
        ), match.numberOfRanges > 1 else {
            return nil
        }
        return nsText.substring(with: match.range(at: 1))
    }

    // MARK: - Language

    /// Extracts the language from the document's `<html ...>` tag only,
    /// so a stray `lang="` in body content can never match.
    /// Returns the primary subtag (e.g. "en" from "en-US").
    static func extractLanguage(fromHTMLTag html: String) -> String? {
        guard let tagRegex = try? NSRegularExpression(
            pattern: "<html\\b[^>]*>", options: [.caseInsensitive]
        ) else {
            return nil
        }
        let nsHTML = html as NSString
        // Only inspect the document head region; <html> appears early.
        let searchLength = min(nsHTML.length, 4096)
        guard let tagMatch = tagRegex.firstMatch(
            in: html, range: NSRange(location: 0, length: searchLength)
        ) else {
            return nil
        }
        let tag = nsHTML.substring(with: tagMatch.range)

        guard let langRegex = try? NSRegularExpression(
            pattern: "\\blang\\s*=\\s*[\"']([^\"']+)[\"']", options: [.caseInsensitive]
        ) else {
            return nil
        }
        let nsTag = tag as NSString
        guard let langMatch = langRegex.firstMatch(
            in: tag, range: NSRange(location: 0, length: nsTag.length)
        ), langMatch.numberOfRanges > 1 else {
            return nil
        }
        let lang = nsTag.substring(with: langMatch.range(at: 1))
        return lang.components(separatedBy: "-").first
    }
}

/// Errors for web page fetching.
enum FetchError: LocalizedError {
    case invalidResponse
    case httpError(statusCode: Int)
    case decodingFailed

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Received an invalid response from the server."
        case .httpError(let code):
            return "Server returned error \(code)."
        case .decodingFailed:
            return "Could not decode the page content."
        }
    }
}

// Helper to convert IANA charset names to Swift encoding
extension String.Encoding {
    init?(ianaCharsetName: String) {
        let cfEncoding = CFStringConvertIANACharSetNameToEncoding(ianaCharsetName as CFString)
        guard cfEncoding != kCFStringEncodingInvalidId else { return nil }
        self = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(cfEncoding))
    }
}
