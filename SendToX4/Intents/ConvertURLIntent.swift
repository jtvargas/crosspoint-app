import AppIntents
import Foundation
import SwiftData

// MARK: - Errors

/// User-facing errors for the Convert URL shortcut.
enum ConvertURLIntentError: Error, CustomLocalizedStringResourceConvertible {
    case invalidURL
    case notAWebPage
    case fetchFailed(String)
    case extractionFailed
    case epubBuildFailed(String)
    case queueWriteFailed(String)

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .invalidURL:
            return "The input is not a valid URL. Please provide a web page link."
        case .notAWebPage:
            return "This doesn't appear to be a web page. CrossX can only convert web URLs to EPUB — images, files, and other content are not supported."
        case .fetchFailed(let detail):
            return "Failed to fetch the web page: \(detail)"
        case .extractionFailed:
            return "Could not extract readable content from this page."
        case .epubBuildFailed(let detail):
            return "Failed to create the EPUB file: \(detail)"
        case .queueWriteFailed(let detail):
            return "Could not save the EPUB to the queue: \(detail)"
        }
    }
}

// MARK: - Intent

/// Siri Shortcut that converts a web page URL to EPUB and queues it for sending to X4.
///
/// Designed to work seamlessly from:
/// - **Shortcuts Share Sheet**: auto-receives the shared URL via `connectToPreviousIntentResult`
/// - **Siri**: asks "Which web page would you like to convert?" when invoked by voice
/// - **Shortcuts app**: can be chained with other actions
///
/// Runs entirely in the background — no app launch required. The EPUB is persisted
/// to disk and tracked via SwiftData so it appears in the Convert tab's queue section
/// the next time the app is opened.
struct ConvertURLIntent: AppIntent {

    static var title: LocalizedStringResource = "Convert to EPUB & Add to Queue"

    static var description = IntentDescription(
        "Converts a web page to EPUB format and queues it for sending to your X4 e-reader.",
        categoryName: "Convert"
    )

    @Parameter(
        title: "Web Page URL",
        description: "The URL of the web page to convert to EPUB",
        inputConnectionBehavior: .connectToPreviousIntentResult
    )
    var urlString: String?

    static var parameterSummary: some ParameterSummary {
        Summary("Convert \(\.$urlString) to EPUB")
    }

    static var openAppWhenRun: Bool = false

    // MARK: - Perform

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<String> {
        // 1. Resolve the URL: auto-received from share sheet, or ask if invoked standalone
        let resolvedURL: URL
        if let raw = urlString?.trimmingCharacters(in: .whitespacesAndNewlines),
           !raw.isEmpty {
            var candidate = raw
            if !candidate.contains("://") {
                candidate = "https://" + candidate
            }
            guard let parsed = URL(string: candidate),
                  parsed.scheme != nil,
                  parsed.host != nil else {
                throw ConvertURLIntentError.invalidURL
            }
            resolvedURL = parsed
        } else {
            throw $urlString.needsValueError(IntentDialog(stringLiteral: loc(.intentProvideURL)))
        }

        // 2. Validate it's a web page URL (not an image, media file, etc.)
        try Self.validateWebPage(url: resolvedURL)

        // 3. Create a SwiftData context (same default store the app uses)
        let modelContext = try Self.makeModelContext()

        // 4. Create Article record for history tracking
        let article = Article(
            url: resolvedURL.absoluteString,
            sourceDomain: resolvedURL.host ?? "unknown"
        )
        modelContext.insert(article)

        // 5. Fetch the web page
        let page: FetchedPage
        do {
            page = try await WebPageFetcher.fetch(url: resolvedURL)
        } catch {
            article.status = .failed
            article.errorMessage = error.localizedDescription
            try? modelContext.save()
            throw ConvertURLIntentError.fetchFailed(error.localizedDescription)
        }

        // 6. Extract content (Twitter -> SwiftSoup -> Readability.js fallback)
        let content: ExtractedContent
        do {
            content = try await Self.extractContent(html: page.html, url: page.finalURL)
        } catch {
            article.status = .failed
            article.errorMessage = "Content extraction failed"
            try? modelContext.save()
            throw ConvertURLIntentError.extractionFailed
        }

        article.title = content.title
        article.author = content.author
        article.sourceDomain = page.finalURL.host ?? resolvedURL.host ?? "unknown"

        // 7. Build the EPUB
        let epubData: Data
        let filename: String
        do {
            let metadata = EPUBBuilder.Metadata(
                title: content.title,
                author: content.author ?? "Unknown",
                language: content.language,
                sourceURL: page.finalURL,
                description: content.description
            )
            epubData = try EPUBBuilder.build(body: content.bodyHTML, metadata: metadata)
            filename = FileNameGenerator.generate(
                title: content.title,
                author: content.author,
                url: page.finalURL
            )
        } catch {
            article.status = .failed
            article.errorMessage = error.localizedDescription
            try? modelContext.save()
            throw ConvertURLIntentError.epubBuildFailed(error.localizedDescription)
        }

        // 8. Enqueue the EPUB for later sending
        article.status = .savedLocally
        do {
            try QueueViewModel.enqueueEPUB(
                epubData: epubData,
                filename: filename,
                article: article,
                modelContext: modelContext
            )
        } catch {
            article.status = .failed
            article.errorMessage = error.localizedDescription
            try? modelContext.save()
            throw ConvertURLIntentError.queueWriteFailed(error.localizedDescription)
        }

        try? modelContext.save()

        // 9. Build a rich result message
        let sizeStr = ByteCountFormatter.string(
            fromByteCount: Int64(epubData.count),
            countStyle: .file
        )
        let queueCount = Self.queueItemCount(modelContext: modelContext)

        let resultValue = loc(.intentQueued, content.title, sizeStr)
        let dialogText = "\(resultValue)\n\(loc(.intentItemsWaiting, queueCount))"

        return .result(
            value: resultValue,
            dialog: IntentDialog(stringLiteral: dialogText)
        )
    }

    // MARK: - URL Validation

    /// Validate that the URL is an HTTP(S) web page — not an image, media file, or non-web scheme.
    private static func validateWebPage(url: URL) throws {
        guard let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              url.host != nil else {
            throw ConvertURLIntentError.invalidURL
        }

        // Reject URLs that point directly to common image/media file extensions
        let pathExtension = url.pathExtension.lowercased()
        let mediaExtensions = ["jpg", "jpeg", "png", "gif", "webp", "svg", "bmp",
                               "mp4", "mov", "avi", "mp3", "wav", "pdf"]
        if mediaExtensions.contains(pathExtension) {
            throw ConvertURLIntentError.notAWebPage
        }
    }

    // MARK: - Private Helpers

    /// Create a ModelContext using the same SwiftData store as the main app.
    private static func makeModelContext() throws -> ModelContext {
        let schema = Schema([
            Article.self,
            DeviceSettings.self,
            ActivityEvent.self,
            QueueItem.self,
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        let container = try ModelContainer(for: schema, configurations: [config])
        return ModelContext(container)
    }

    /// Multi-strategy content extraction (same pipeline as ConvertViewModel).
    @MainActor
    private static func extractContent(html: String, url: URL) async throws -> ExtractedContent {
        // Twitter/X: use fxtwitter API
        if TwitterExtractor.canHandle(url: url) {
            if let content = try await TwitterExtractor.extract(from: url) {
                return content
            }
        }

        // SwiftSoup heuristic extraction
        if let content = try ContentExtractor.extract(from: html, url: url) {
            return content
        }

        // Readability.js fallback via WKWebView
        let readability = ReadabilityExtractor()
        if let content = try await readability.extract(html: html, baseURL: url) {
            return content
        }

        throw ConvertURLIntentError.extractionFailed
    }

    /// Count queued items for the result dialog.
    private static func queueItemCount(modelContext: ModelContext) -> Int {
        let descriptor = FetchDescriptor<QueueItem>()
        return (try? modelContext.fetchCount(descriptor)) ?? 0
    }
}
