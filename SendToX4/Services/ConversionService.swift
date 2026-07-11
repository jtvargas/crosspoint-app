import Foundation
import SwiftSoup

/// Options controlling a single URL→EPUB conversion.
struct ConversionOptions {
    /// Preserve article images in the generated EPUB (downloaded and embedded).
    /// Wired to `DeviceSettings.includeImages`; off by default.
    var includeImages = false

    /// Download caps applied when `includeImages` is enabled.
    var imageLimits = ImageLimits.default
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
            pageLanguage: page.language,
            sanitizerOptions: SanitizerOptions(keepImages: options.includeImages)
        )

        onPhase(.building)
        let metadata = EPUBBuilder.Metadata(
            title: content.title,
            author: content.author ?? "Unknown",
            language: content.language,
            sourceURL: page.finalURL,
            description: content.description
        )

        // Optional image embedding — failures degrade to alt text or, on any
        // surprise, to a text-only EPUB. Never fails the conversion.
        var bodyHTML = content.bodyHTML
        var embeddedImages: [EPUBImage] = []
        if options.includeImages && !content.images.isEmpty {
            let (downloaded, failed) = await ImageDownloader.download(
                content.images, limits: options.imageLimits
            )
            embeddedImages = markCover(downloaded)
            if !failed.isEmpty {
                bodyHTML = replaceFailedImages(in: bodyHTML, failed: failed)
            }
        }

        let epubData = try EPUBBuilder.build(
            body: bodyHTML, metadata: metadata, images: embeddedImages
        )
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

    // MARK: - Image Post-Processing

    /// Cover threshold: the first image at least this large becomes the
    /// EPUB cover (EPUB 2.0 `<meta name="cover">` idiom).
    private static let coverMinDimension = 300

    /// Marks the first sufficiently large image as the cover.
    private func markCover(_ images: [EPUBImage]) -> [EPUBImage] {
        var result = images
        if let index = result.firstIndex(where: {
            $0.width >= Self.coverMinDimension && $0.height >= Self.coverMinDimension
        }) {
            result[index].isCover = true
        }
        return result
    }

    /// Replaces `<img>` placeholders whose download failed with their alt
    /// text (italic paragraph), or removes them when no alt is available.
    /// Any parsing trouble returns the body unchanged (images degrade to
    /// broken refs at worst — never a failed conversion).
    private func replaceFailedImages(in bodyHTML: String, failed: [ImageRef]) -> String {
        do {
            let doc = try SwiftSoup.parseBodyFragment(bodyHTML)
            guard let body = doc.body() else { return bodyHTML }
            doc.outputSettings()
                .syntax(syntax: OutputSettings.Syntax.xml)
                .escapeMode(Entities.EscapeMode.xhtml)
                .charset(String.Encoding.utf8)

            for ref in failed {
                for img in try body.select("img[src=\(ref.placeholderPath)]") {
                    let alt = ref.alt.trimmingCharacters(in: .whitespacesAndNewlines)
                    if alt.isEmpty {
                        try img.remove()
                    } else {
                        let paragraph = try Element(Tag.valueOf("p"), "")
                        let emphasis = try paragraph.appendElement("em")
                        try emphasis.text("[\(alt)]")
                        try img.replaceWith(paragraph)
                    }
                }
            }
            return try body.html()
        } catch {
            DebugLogger.log(
                "Failed-image fallback skipped: \(error.localizedDescription)",
                level: .warning, category: .conversion
            )
            return bodyHTML
        }
    }

    // MARK: - Extraction Cascade

    /// Multi-strategy extraction: Twitter API → SwiftSoup → Readability.js fallback.
    ///
    /// A fresh `ReadabilityExtractor` is created per call so concurrent
    /// conversions can never clobber each other's continuation state.
    private func extractContent(
        html: String,
        url: URL,
        pageLanguage: String,
        sanitizerOptions: SanitizerOptions = SanitizerOptions()
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
        if let content = try ContentExtractor.extract(from: html, url: url, options: sanitizerOptions) {
            return content
        }

        // Readability.js fallback (pre-fetched HTML, hidden WKWebView).
        let readability = ReadabilityExtractor()
        let fallback = try await readability.extract(
            html: html, baseURL: url, language: pageLanguage, options: sanitizerOptions
        )
        if let fallback {
            return fallback
        }

        throw EPUBError.contentTooShort
    }
}
