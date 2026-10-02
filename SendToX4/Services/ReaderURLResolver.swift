import Foundation
import SwiftSoup

/// URL-only normalization for reader wrappers; JavaScript rendering belongs to extraction.
nonisolated enum ReaderURLResolver {
    static func isReaderURL(_ url: URL) -> Bool {
        guard let path = URLComponents(url: url, resolvingAgainstBaseURL: false)?.percentEncodedPath else {
            return false
        }
        return path.components(separatedBy: "/").dropLast().contains {
            $0.removingPercentEncoding?.lowercased() == "reader"
        }
    }

    /// Prefer an explicit canonical link, then the unwrapped path, then the input.
    /// Non-reader URLs are intentionally left alone.
    static func candidates(for url: URL, html: String? = nil) -> [URL] {
        guard isReaderURL(url) else { return [url] }
        var result: [URL] = []
        if let html, let canonical = canonicalURL(in: html), canonical != url {
            result.append(canonical)
        }
        if var components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            // Work on encoded segments so %2F, query values, and fragments survive unchanged.
            let segments = components.percentEncodedPath.components(separatedBy: "/")
            components.percentEncodedPath = segments.enumerated().filter { index, segment in
                index == segments.count - 1 || segment.removingPercentEncoding?.lowercased() != "reader"
            }.map(\.element).joined(separator: "/")
            if let unwrapped = components.url, unwrapped != url, !result.contains(unwrapped) {
                result.append(unwrapped)
            }
        }
        result.append(url)
        return result
    }

    private static func canonicalURL(in html: String) -> URL? {
        guard let doc = try? SwiftSoup.parse(html),
              let links = try? doc.select("link[rel][href]") else { return nil }
        for link in links {
            guard let rel = try? link.attr("rel"),
                  rel.split(whereSeparator: \.isWhitespace).contains(where: { $0.lowercased() == "canonical" }),
                  let href = try? link.attr("href"),
                  let url = URL(string: href.trimmingCharacters(in: .whitespacesAndNewlines)),
                  let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme),
                  let host = url.host, !host.isEmpty else { continue }
            return url
        }
        return nil
    }

    /// Cheap empty-shell check, not article extraction or a JavaScript-rendering policy.
    static func hasNoContent(_ html: String) -> Bool {
        guard let doc = try? SwiftSoup.parse(html), let body = doc.body() else { return false }
        _ = try? body.select("script, style, noscript, template").remove()
        return (try? body.text().trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) == true
    }
}
