import Foundation
import WebKit

/// Serves EPUB content to the reader WKWebView over a custom scheme,
/// streaming resources lazily from the zip — nothing is unzipped to disk.
///
/// URLs:
/// - `crossx-epub:///__reader__` → the combined continuous-scroll document
/// - `crossx-epub:///<reader href>` → package resource (images, css), with
///   the href resolved against the OPF directory
final class EPUBSchemeHandler: NSObject, WKURLSchemeHandler {

    static let scheme = "crossx-epub"
    static let readerURL = URL(string: "\(scheme):///__reader__")!

    private let document: EPUBDocument

    init(document: EPUBDocument) {
        self.document = document
    }

    nonisolated func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        MainActor.assumeIsolated {
            handle(urlSchemeTask)
        }
    }

    nonisolated func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {
        // Responses are delivered synchronously in start; nothing to cancel.
    }

    private func handle(_ task: WKURLSchemeTask) {
        guard let url = task.request.url else {
            task.didFailWithError(URLError(.badURL))
            return
        }

        let path = url.path.hasPrefix("/") ? String(url.path.dropFirst()) : url.path

        let data: Data?
        let mimeType: String
        if path == "__reader__" {
            data = Data(document.combinedHTML().utf8)
            mimeType = "text/html"
        } else {
            data = document.resource(at: document.packagePath(forReaderHref: path))
            mimeType = Self.mimeType(forPath: path)
        }

        guard let data else {
            task.didFailWithError(URLError(.fileDoesNotExist))
            return
        }

        let response = URLResponse(
            url: url,
            mimeType: mimeType,
            expectedContentLength: data.count,
            textEncodingName: mimeType == "text/html" ? "utf-8" : nil
        )
        task.didReceive(response)
        task.didReceive(data)
        task.didFinish()
    }

    private static func mimeType(forPath path: String) -> String {
        switch (path as NSString).pathExtension.lowercased() {
        case "jpg", "jpeg": return "image/jpeg"
        case "png": return "image/png"
        case "gif": return "image/gif"
        case "webp": return "image/webp"
        case "svg": return "image/svg+xml"
        case "css": return "text/css"
        case "xhtml", "html": return "text/html"
        default: return "application/octet-stream"
        }
    }
}
