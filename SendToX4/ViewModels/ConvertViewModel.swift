import Foundation
import SwiftData

/// Orchestrates the web page -> EPUB -> device pipeline.
@MainActor
@Observable
final class ConvertViewModel {

    // MARK: - Published State

    var urlString = ""
    var statusMessage = ""
    var isProcessing = false
    var currentPhase: ConversionStatus = .pending
    var lastError: String?
    var lastEPUBData: Data?
    var lastFilename: String?

    // MARK: - Private

    private let readabilityExtractor = ReadabilityExtractor()

    /// The current phase label shown to the user.
    var phaseLabel: String {
        switch currentPhase {
        case .pending: return "Ready"
        case .fetching: return "Fetching page..."
        case .extracting: return "Extracting content..."
        case .building: return "Building EPUB..."
        case .sending: return "Sending to X4..."
        case .sent: return "Sent!"
        case .savedLocally: return "Saved locally"
        case .failed: return "Failed"
        }
    }

    // MARK: - Convert & Send Pipeline

    /// Run the full pipeline: fetch -> extract -> build EPUB -> send to device.
    /// Creates an Article record in SwiftData.
    func convertAndSend(
        modelContext: ModelContext,
        deviceVM: DeviceViewModel,
        settings: DeviceSettings?
    ) async {
        guard let url = validatedURL else {
            lastError = "Please enter a valid URL."
            return
        }

        guard !deviceVM.isUploading else {
            lastError = "An upload is already in progress."
            return
        }

        isProcessing = true
        lastError = nil
        lastEPUBData = nil
        lastFilename = nil

        let article = Article(url: url.absoluteString, sourceDomain: url.host ?? "unknown")
        modelContext.insert(article)

        do {
            // Phase 1: Fetch
            currentPhase = .fetching
            article.status = .fetching
            let page = try await WebPageFetcher.fetch(url: url)

            // Phase 2: Extract
            currentPhase = .extracting
            article.status = .extracting
            let content = try await extractContent(html: page.html, url: page.finalURL)

            article.title = content.title
            article.author = content.author
            article.sourceDomain = page.finalURL.host ?? url.host ?? "unknown"

            // Phase 3: Build EPUB
            currentPhase = .building
            article.status = .building
            let metadata = EPUBBuilder.Metadata(
                title: content.title,
                author: content.author ?? "Unknown",
                language: content.language,
                sourceURL: page.finalURL,
                description: content.description
            )
            let epubData = try EPUBBuilder.build(body: content.bodyHTML, metadata: metadata)
            let filename = FileNameGenerator.generate(
                title: content.title, author: content.author, url: page.finalURL
            )

            lastEPUBData = epubData
            lastFilename = filename

            // Phase 4: Send to device (if connected)
            if deviceVM.isConnected {
                currentPhase = .sending
                article.status = .sending
                let folder = settings?.convertFolder ?? "content"
                try await deviceVM.upload(data: epubData, filename: filename, toFolder: folder)

                currentPhase = .sent
                article.status = .sent
                statusMessage = "Sent \"\(content.title.truncated(to: 40))\" to X4"
            } else {
                // Save locally if device not connected
                currentPhase = .savedLocally
                article.status = .savedLocally
                statusMessage = "EPUB ready. Connect to X4 to send."
            }

        } catch {
            currentPhase = .failed
            article.status = .failed
            article.errorMessage = error.localizedDescription
            lastError = error.localizedDescription
            statusMessage = ""
        }

        isProcessing = false
    }

    /// Convert only (no send) — generates EPUB for local save.
    func convertOnly(modelContext: ModelContext) async -> Data? {
        guard let url = validatedURL else {
            lastError = "Please enter a valid URL."
            return nil
        }

        isProcessing = true
        lastError = nil

        let article = Article(url: url.absoluteString, sourceDomain: url.host ?? "unknown")
        modelContext.insert(article)

        do {
            currentPhase = .fetching
            article.status = .fetching
            let page = try await WebPageFetcher.fetch(url: url)

            currentPhase = .extracting
            article.status = .extracting
            let content = try await extractContent(html: page.html, url: page.finalURL)

            article.title = content.title
            article.author = content.author
            article.sourceDomain = page.finalURL.host ?? url.host ?? "unknown"

            currentPhase = .building
            article.status = .building
            let metadata = EPUBBuilder.Metadata(
                title: content.title,
                author: content.author ?? "Unknown",
                language: content.language,
                sourceURL: page.finalURL,
                description: content.description
            )
            let epubData = try EPUBBuilder.build(body: content.bodyHTML, metadata: metadata)
            let filename = FileNameGenerator.generate(
                title: content.title, author: content.author, url: page.finalURL
            )

            lastEPUBData = epubData
            lastFilename = filename

            currentPhase = .savedLocally
            article.status = .savedLocally
            statusMessage = "EPUB created: \"\(content.title.truncated(to: 40))\""

            isProcessing = false
            return epubData

        } catch {
            currentPhase = .failed
            article.status = .failed
            article.errorMessage = error.localizedDescription
            lastError = error.localizedDescription
            isProcessing = false
            return nil
        }
    }

    /// Resend a previously converted article.
    func resend(
        article: Article,
        deviceVM: DeviceViewModel,
        settings: DeviceSettings?,
        modelContext: ModelContext
    ) async {
        guard deviceVM.isConnected else {
            lastError = "X4 is not connected."
            return
        }

        isProcessing = true
        lastError = nil

        guard let url = URL(string: article.url) else {
            lastError = "Invalid article URL."
            isProcessing = false
            return
        }

        do {
            // Re-generate the EPUB
            currentPhase = .fetching
            article.status = .fetching
            let page = try await WebPageFetcher.fetch(url: url)

            currentPhase = .extracting
            article.status = .extracting
            let content = try await extractContent(html: page.html, url: page.finalURL)

            currentPhase = .building
            article.status = .building
            let metadata = EPUBBuilder.Metadata(
                title: content.title,
                author: content.author ?? "Unknown",
                language: content.language,
                sourceURL: page.finalURL,
                description: content.description
            )
            let epubData = try EPUBBuilder.build(body: content.bodyHTML, metadata: metadata)
            let filename = FileNameGenerator.generate(
                title: content.title, author: content.author, url: page.finalURL
            )

            currentPhase = .sending
            article.status = .sending
            let folder = settings?.convertFolder ?? "content"
            try await deviceVM.upload(data: epubData, filename: filename, toFolder: folder)

            currentPhase = .sent
            article.status = .sent
            statusMessage = "Re-sent \"\(content.title.truncated(to: 40))\" to X4"

        } catch {
            currentPhase = .failed
            article.status = .failed
            article.errorMessage = error.localizedDescription
            lastError = error.localizedDescription
        }

        isProcessing = false
    }

    /// Reconvert an existing article and return the EPUB data + filename for sharing.
    /// Does NOT create a new Article — reuses the existing record.
    func reconvertForShare(
        article: Article,
        modelContext: ModelContext
    ) async -> (data: Data, filename: String)? {
        guard let url = URL(string: article.url) else {
            lastError = "Invalid article URL."
            return nil
        }

        isProcessing = true
        lastError = nil

        do {
            currentPhase = .fetching
            article.status = .fetching
            let page = try await WebPageFetcher.fetch(url: url)

            currentPhase = .extracting
            article.status = .extracting
            let content = try await extractContent(html: page.html, url: page.finalURL)

            article.title = content.title
            article.author = content.author
            article.sourceDomain = page.finalURL.host ?? url.host ?? "unknown"

            currentPhase = .building
            article.status = .building
            let metadata = EPUBBuilder.Metadata(
                title: content.title,
                author: content.author ?? "Unknown",
                language: content.language,
                sourceURL: page.finalURL,
                description: content.description
            )
            let epubData = try EPUBBuilder.build(body: content.bodyHTML, metadata: metadata)
            let filename = FileNameGenerator.generate(
                title: content.title, author: content.author, url: page.finalURL
            )

            lastEPUBData = epubData
            lastFilename = filename

            currentPhase = .savedLocally
            article.status = .savedLocally
            isProcessing = false
            return (epubData, filename)

        } catch {
            currentPhase = .failed
            article.status = .failed
            article.errorMessage = error.localizedDescription
            lastError = error.localizedDescription
            isProcessing = false
            return nil
        }
    }

    /// Reset state for a new conversion.
    func reset() {
        urlString = ""
        statusMessage = ""
        currentPhase = .pending
        lastError = nil
        lastEPUBData = nil
        lastFilename = nil
    }

    // MARK: - Private Helpers

    /// Validate and parse the URL string.
    var validatedURL: URL? {
        var str = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        if !str.isEmpty && !str.contains("://") {
            str = "https://" + str
        }
        return URL(string: str)
    }

    /// Multi-strategy extraction: Twitter API → SwiftSoup → Readability.js fallback.
    private func extractContent(html: String, url: URL) async throws -> ExtractedContent {
        // Twitter/X: use fxtwitter API (JS-only SPA, HTML has no content)
        if TwitterExtractor.canHandle(url: url) {
            if let content = try await TwitterExtractor.extract(from: url) {
                return content
            }
        }

        // Try fast SwiftSoup extraction first
        if let content = try ContentExtractor.extract(from: html, url: url) {
            return content
        }

        // Fallback to Readability.js (using pre-fetched HTML to avoid WKWebView entitlement issues)
        if let content = try await readabilityExtractor.extract(html: html, baseURL: url) {
            return content
        }

        // All strategies failed
        throw EPUBError.contentTooShort
    }
}
