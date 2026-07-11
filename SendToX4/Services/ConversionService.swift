import Foundation

/// Options controlling a single URL→EPUB conversion.
struct ConversionOptions {
    /// Preserve article images in the generated EPUB (downloaded and embedded).
    /// Wired to `DeviceSettings.includeImages`; off by default.
    var includeImages = false
}

/// The product of a successful conversion.
struct ConversionResult {
    let epubData: Data
    let filename: String
    let content: ExtractedContent
    let finalURL: URL
}

/// Single home of the URL → fetch → extract → build EPUB pipeline.
///
/// Every conversion entry point (Convert tab, RSS batch, Siri intent) calls
/// this service instead of duplicating the sequence. Call sites keep their
/// own post-processing (send to device / queue / share) and map phases onto
/// their UI/Article state via `onPhase`.
@MainActor
struct ConversionService {

    /// Injected for testability; defaults to the real network fetch.
    var fetch: (URL) async throws -> FetchedPage = { try await WebPageFetcher.fetch(url: $0) }

    /// Injected for testability; defaults to the fxtwitter API extractor.
    var twitterExtract: (URL) async throws -> ExtractedContent? = { try await TwitterExtractor.extract(from: $0) }

    /// Run the full pipeline for one URL.
    ///
    /// - Parameters:
    ///   - url: The web page URL.
    ///   - options: Conversion options (image support etc.).
    ///   - onPhase: Called as the pipeline advances (`.fetching`, `.extracting`,
    ///     `.building`) so callers can mirror progress onto their state.
    /// - Returns: The EPUB data, generated filename, and extracted content.
    func convert(
        url: URL,
        options: ConversionOptions = ConversionOptions(),
        onPhase: (ConversionStatus) -> Void = { _ in }
    ) async throws -> ConversionResult {
        onPhase(.fetching)
        let page = try await fetch(url)

        onPhase(.extracting)
        let content = try await extractContent(
            html: page.html,
            url: page.finalURL,
            pageLanguage: page.language
        )

        onPhase(.building)
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

        return ConversionResult(
            epubData: epubData,
            filename: filename,
            content: content,
            finalURL: page.finalURL
        )
    }

    // MARK: - Extraction Cascade

    /// Multi-strategy extraction: Twitter API → SwiftSoup → Readability.js fallback.
    ///
    /// A fresh `ReadabilityExtractor` is created per call so concurrent
    /// conversions can never clobber each other's continuation state.
    private func extractContent(
        html: String,
        url: URL,
        pageLanguage: String
    ) async throws -> ExtractedContent {
        // Twitter/X: use fxtwitter API (JS-only SPA, HTML has no content).
        // Errors are swallowed so an fxtwitter outage falls through to the
        // generic extractors instead of failing the conversion outright.
        if TwitterExtractor.canHandle(url: url) {
            if let content = try? await twitterExtract(url), let content {
                // Twitter bodies are built tag-by-tag but still get normalized
                // to XHTML like every other source.
                let xhtml = (try? HTMLSanitizer.toXHTML(content.bodyHTML)) ?? content.bodyHTML
                return ExtractedContent(
                    title: content.title,
                    author: content.author,
                    description: content.description,
                    language: content.language,
                    bodyHTML: xhtml
                )
            }
        }

        // Fast SwiftSoup heuristic extraction.
        if let content = try ContentExtractor.extract(from: html, url: url) {
            return content
        }

        // Readability.js fallback (pre-fetched HTML, hidden WKWebView).
        let readability = ReadabilityExtractor()
        if let content = try await readability.extract(
            html: html, baseURL: url, language: pageLanguage
        ) {
            return content
        }

        throw EPUBError.contentTooShort
    }
}
