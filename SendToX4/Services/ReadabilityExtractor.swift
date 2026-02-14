import Foundation
import WebKit

/// Fallback content extractor using Mozilla Readability.js in a hidden WKWebView.
/// Used when SwiftSoup heuristic extraction produces insufficient content.
@MainActor
final class ReadabilityExtractor: NSObject {
    
    private var webView: WKWebView?
    private var continuation: CheckedContinuation<ExtractedContent?, Error>?
    
    /// Readability.js source loaded from the app bundle.
    private static let readabilityJS: String? = {
        guard let url = Bundle.main.url(forResource: "readability", withExtension: "js"),
              let source = try? String(contentsOf: url, encoding: .utf8) else {
            return nil
        }
        return source
    }()
    
    /// The extraction script that runs Readability and returns results as JSON.
    private static let extractionScript = """
    (function() {
        try {
            var article = new Readability(document.cloneNode(true)).parse();
            if (article) {
                return JSON.stringify({
                    title: article.title || '',
                    content: article.content || '',
                    textContent: article.textContent || '',
                    byline: article.byline || '',
                    excerpt: article.excerpt || ''
                });
            }
            return null;
        } catch(e) {
            return null;
        }
    })();
    """
    
    /// Extract article content using Readability.js in a hidden WebView.
    /// Uses loadHTMLString to avoid web-browser-engine entitlement requirements on iOS 26+.
    /// - Parameters:
    ///   - html: The pre-fetched HTML string.
    ///   - baseURL: The original page URL (used for resolving relative paths).
    /// - Returns: Extracted content, or nil if extraction fails.
    func extract(html: String, baseURL: URL) async throws -> ExtractedContent? {
        guard ReadabilityExtractor.readabilityJS != nil else {
            return nil // Readability.js not bundled
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            
            let config = WKWebViewConfiguration()
            config.suppressesIncrementalRendering = true
            
            let webView = WKWebView(frame: .zero, configuration: config)
            webView.navigationDelegate = self
            self.webView = webView
            
            webView.loadHTMLString(html, baseURL: baseURL)
            
            // Timeout after 30 seconds
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(30))
                if let cont = self?.continuation {
                    self?.continuation = nil
                    self?.cleanup()
                    cont.resume(returning: nil)
                }
            }
        }
    }
    
    private func cleanup() {
        webView?.stopLoading()
        webView?.navigationDelegate = nil
        webView = nil
    }
}

extension ReadabilityExtractor: WKNavigationDelegate {
    
    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor in
            await self.performExtraction(in: webView)
        }
    }
    
    nonisolated func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor in
            if let cont = self.continuation {
                self.continuation = nil
                self.cleanup()
                cont.resume(returning: nil)
            }
        }
    }
    
    nonisolated func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor in
            if let cont = self.continuation {
                self.continuation = nil
                self.cleanup()
                cont.resume(returning: nil)
            }
        }
    }
    
    @MainActor
    private func performExtraction(in webView: WKWebView) async {
        guard let readabilityJS = ReadabilityExtractor.readabilityJS else {
            resumeWithResult(nil)
            return
        }
        
        do {
            // Inject Readability.js
            try await webView.evaluateJavaScript(readabilityJS)
            
            // Run extraction
            let result = try await webView.evaluateJavaScript(Self.extractionScript)
            
            guard let jsonString = result as? String,
                  let jsonData = jsonString.data(using: .utf8),
                  let json = try JSONSerialization.jsonObject(with: jsonData) as? [String: String] else {
                resumeWithResult(nil)
                return
            }
            
            let content = json["content"] ?? ""
            let textContent = json["textContent"] ?? ""
            
            // Validate content length
            guard textContent.count >= 400 else {
                resumeWithResult(nil)
                return
            }
            
            // Sanitize the Readability output
            let sanitized = try HTMLSanitizer.sanitize(content)
            let xhtml = try HTMLSanitizer.toXHTML(sanitized)
            
            let extracted = ExtractedContent(
                title: json["title"]?.condensed ?? "Untitled",
                author: json["byline"]?.condensed,
                description: json["excerpt"]?.condensed ?? "",
                language: "en",
                bodyHTML: xhtml
            )
            
            resumeWithResult(extracted)
        } catch {
            resumeWithResult(nil)
        }
    }
    
    @MainActor
    private func resumeWithResult(_ result: ExtractedContent?) {
        if let cont = continuation {
            continuation = nil
            cleanup()
            cont.resume(returning: result)
        }
    }
}
