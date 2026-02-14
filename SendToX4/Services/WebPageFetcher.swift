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
    
    /// Fetch the HTML content of a web page.
    /// Follows redirects automatically and captures the final URL.
    static func fetch(url: URL) async throws -> FetchedPage {
        var request = URLRequest(url: url)
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 26_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Mobile/15E148 Safari/604.1",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw FetchError.invalidResponse
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            throw FetchError.httpError(statusCode: httpResponse.statusCode)
        }
        
        // Determine encoding from response or default to UTF-8
        let encoding = httpResponse.textEncodingName
            .flatMap { String.Encoding(ianaCharsetName: $0) }
            ?? .utf8
        
        guard let html = String(data: data, encoding: encoding)
                ?? String(data: data, encoding: .utf8)
                ?? String(data: data, encoding: .isoLatin1) else {
            throw FetchError.decodingFailed
        }
        
        let finalURL = httpResponse.url ?? url
        
        // Extract language from HTML
        let language = extractLanguage(from: html) ?? "en"
        
        return FetchedPage(html: html, finalURL: finalURL, language: language)
    }
    
    /// Extracts the language attribute from the HTML tag.
    private static func extractLanguage(from html: String) -> String? {
        // Quick regex-free approach: find lang="..." or xml:lang="..."
        guard let langRange = html.range(of: "lang=\"", options: .caseInsensitive) else {
            return nil
        }
        let start = langRange.upperBound
        guard let endRange = html[start...].range(of: "\"") else {
            return nil
        }
        let lang = String(html[start..<endRange.lowerBound])
        // Return just the primary language tag (e.g., "en" from "en-US")
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
