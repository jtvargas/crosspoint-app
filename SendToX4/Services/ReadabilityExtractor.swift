import Foundation
import WebKit

/// Readability.js extraction from pre-fetched HTML or a JavaScript-rendered page.
@MainActor
final class ReadabilityExtractor: NSObject {
    private var webView: WKWebView?
    private var continuation: CheckedContinuation<ExtractedContent?, Error>?
    private var timeoutTask: Task<Void, Never>?
    private var extractionTask: Task<Void, Never>?
    private var waitsForRendering = false
    private var pageLanguage = "en"
    private var baseURL: URL?
    private var sanitizerOptions = SanitizerOptions()

    private static let readabilityJS: String? = {
        guard let url = Bundle.main.url(forResource: "readability", withExtension: "js"),
              let source = try? String(contentsOf: url, encoding: .utf8) else {
            return nil
        }
        return source
    }()

    private static let extractionScript = """
    (function() {
        var article = new Readability(document.cloneNode(true)).parse();
        if (!article) return null;
        return JSON.stringify({
            title: article.title || '',
            content: article.content || '',
            textContent: article.textContent || '',
            byline: article.byline || '',
            excerpt: article.excerpt || '',
            language: document.documentElement.lang || ''
        });
    })();
    """

    /// Keeps the pre-fetched fast path without a second page navigation.
    func extract(
        html: String,
        baseURL: URL,
        language: String = "en",
        options: SanitizerOptions = SanitizerOptions()
    ) async throws -> ExtractedContent? {
        try await extract(html: html, url: baseURL, language: language, options: options)
    }

    /// Standard WKWebView HTTPS navigation needs no alternative-browser-engine entitlement.
    func extract(
        url: URL,
        language: String = "en",
        options: SanitizerOptions = SanitizerOptions()
    ) async throws -> ExtractedContent? {
        try await extract(html: nil, url: url, language: language, options: options)
    }

    private func extract(
        html: String?, url: URL, language: String, options: SanitizerOptions
    ) async throws -> ExtractedContent? {
        try Task.checkCancellation()
        guard Self.readabilityJS != nil, continuation == nil else { return nil }
        pageLanguage = language
        baseURL = url
        sanitizerOptions = options
        waitsForRendering = html == nil

        // Capture this operation's view so delayed cancellation cannot affect a
        // subsequent extraction on the same instance.
        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        config.websiteDataStore = .nonPersistent()
        let view = WKWebView(frame: CGRect(x: 0, y: 0, width: 1024, height: 768), configuration: config)
        webView = view
        view.navigationDelegate = self

        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                if let html {
                    view.loadHTMLString(html, baseURL: url)
                } else {
                    view.load(URLRequest(url: url, timeoutInterval: 30))
                }
                // Deadline covers navigation, rendering and extraction together.
                timeoutTask = Task { [weak self, weak view] in
                    do { try await Task.sleep(for: .seconds(30)) } catch { return }
                    guard let self, let view, self.webView === view else { return }
                    self.finish(.success(nil))
                }
            }
        } onCancel: {
            Task { @MainActor [weak self, weak view] in
                guard let self, let view, self.webView === view else { return }
                self.finish(.failure(CancellationError()))
            }
        }
    }

    private func finish(_ result: Result<ExtractedContent?, Error>) {
        let pending = continuation
        continuation = nil
        timeoutTask?.cancel()
        timeoutTask = nil
        extractionTask?.cancel()
        extractionTask = nil
        webView?.navigationDelegate = nil
        webView?.stopLoading()
        webView = nil
        pending?.resume(with: result)
    }

    private func extractDOM(in view: WKWebView) async throws -> ExtractedContent? {
        guard let source = Self.readabilityJS else { return nil }
        // Isolate our parser from globals supplied by the live page's scripts.
        _ = try await view.evaluateJavaScript(source, in: nil, contentWorld: .defaultClient)
        let result = try await view.evaluateJavaScript(Self.extractionScript, in: nil, contentWorld: .defaultClient)
        try Task.checkCancellation()
        guard webView === view,
              let jsonString = result as? String,
              let data = jsonString.data(using: .utf8),
              let json = try JSONSerialization.jsonObject(with: data) as? [String: String],
              let text = json["textContent"], text.count >= 400 else { return nil }
        let sanitized = try HTMLSanitizer.sanitizeToXHTML(
            json["content"] ?? "",
            baseURI: view.url?.absoluteString ?? baseURL?.absoluteString ?? "",
            options: sanitizerOptions
        )
        let language = json["language"] ?? ""
        return ExtractedContent(
            title: json["title"]?.condensed ?? "Untitled",
            author: json["byline"]?.condensed,
            description: json["excerpt"]?.condensed ?? "",
            language: language.isEmpty ? pageLanguage : language.components(separatedBy: "-")[0],
            bodyHTML: sanitized.bodyHTML,
            images: sanitized.images
        )
    }

    private func beginExtraction(in view: WKWebView) {
        guard webView === view, continuation != nil else { return }
        extractionTask?.cancel()
        extractionTask = Task { [weak self] in
            guard let self else { return }
            do {
                if !self.waitsForRendering {
                    let content = try await self.extractDOM(in: view)
                    try Task.checkCancellation()
                    guard self.webView === view else { return }
                    self.finish(.success(content))
                    return
                }

                var previousLength = 0
                var stableSamples = 0
                while !Task.isCancelled, self.webView === view {
                    let result = try await view.evaluateJavaScript(
                        "document.body ? document.body.innerText.trim().length : 0",
                        in: nil, contentWorld: .defaultClient
                    )
                    try Task.checkCancellation()
                    let length = result as? Int ?? 0
                    stableSamples = length >= 400 && length == previousLength ? stableSamples + 1 : 0
                    previousLength = length
                    // Wait for a second of stable text, then validate the actual
                    // article, not just navigation/footer text. Keep polling if nil.
                    if stableSamples >= 2, let content = try await self.extractDOM(in: view) {
                        try Task.checkCancellation()
                        guard self.webView === view else { return }
                        self.finish(.success(content))
                        return
                    }
                    try await Task.sleep(for: .milliseconds(500))
                }
            } catch {
                guard !Task.isCancelled, self.webView === view else { return }
                self.finish(.success(nil))
            }
        }
    }
}

extension ReadabilityExtractor: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        beginExtraction(in: webView)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        guard self.webView === webView else { return }
        finish(.success(nil))
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        guard self.webView === webView else { return }
        finish(.success(nil))
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        guard self.webView === webView else { return }
        finish(.success(nil))
    }
}
