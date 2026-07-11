import Foundation
import SwiftData

/// Orchestrates the web page -> EPUB -> device pipeline.
///
/// The actual fetch/extract/build sequence lives in `ConversionService`;
/// this view model owns UI state and the send/queue/share post-processing.
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

    /// Set to `true` when a review prompt should be shown. The View observes this.
    var shouldRequestReview = false

    // MARK: - Private

    private let conversionService = ConversionService()

    /// The current phase label shown to the user.
    var phaseLabel: String {
        switch currentPhase {
        case .pending: return loc(.phaseReady)
        case .fetching: return loc(.phaseFetching)
        case .extracting: return loc(.phaseExtracting)
        case .building: return loc(.phaseBuilding)
        case .sending: return loc(.phaseSending)
        case .sent: return loc(.phaseSent)
        case .savedLocally: return loc(.phaseSavedLocally)
        case .failed: return loc(.phaseFailed)
        }
    }

    // MARK: - Convert & Send Pipeline

    /// Run the full pipeline: fetch -> extract -> build EPUB -> send to device.
    /// Creates an Article record in SwiftData.
    func convertAndSend(
        modelContext: ModelContext,
        deviceVM: DeviceViewModel,
        queueVM: QueueViewModel,
        settings: DeviceSettings?,
        toast: ToastManager? = nil
    ) async {
        guard let url = validatedURL else {
            lastError = loc(.enterValidURL)
            toast?.showError(loc(.enterValidURL))
            return
        }

        guard !deviceVM.isUploading else {
            lastError = loc(.uploadAlreadyInProgress)
            toast?.showError(loc(.uploadAlreadyInProgress))
            return
        }

        // Duplicate prevention: block if this URL is already queued
        if QueueViewModel.isURLQueued(url.absoluteString, modelContext: modelContext) {
            lastError = loc(.urlAlreadyQueued)
            toast?.showError(loc(.urlAlreadyQueued))
            return
        }

        isProcessing = true
        lastError = nil
        lastEPUBData = nil
        lastFilename = nil

        let article = Article(url: url.absoluteString, sourceDomain: url.host ?? "unknown")
        modelContext.insert(article)

        DebugLogger.log(
            "Conversion started: \(url.absoluteString)",
            level: .info, category: .conversion
        )

        do {
            let result = try await runConversion(url: url, article: article, settings: settings)

            lastEPUBData = result.epubData
            lastFilename = result.filename

            // Send to device (if connected and not busy deleting)
            if deviceVM.isConnected && !deviceVM.isBatchDeleting {
                currentPhase = .sending
                article.status = .sending
                let folder = settings?.convertFolder ?? "content"
                let uploadData = await EPUBOptimizer.optimizeIfNeeded(
                    result.epubData,
                    filename: result.filename,
                    enabled: settings?.optimizeEPUBUpload ?? true
                )
                try await deviceVM.upload(data: uploadData, filename: result.filename, toFolder: folder)

                currentPhase = .sent
                article.status = .sent
                statusMessage = loc(.sentArticleToX4, result.content.title.truncated(to: 40))
                toast?.showSuccess(loc(.phaseSent), subtitle: result.content.title.truncated(to: 50))

                DebugLogger.log(
                    "Conversion complete + sent: '\(result.content.title)' (\(result.filename))",
                    level: .info, category: .conversion
                )

                if ReviewPromptManager.shouldPromptAfterSuccess() {
                    shouldRequestReview = true
                }

                // Auto-reset after delay so the button reverts to idle
                try? await Task.sleep(for: .seconds(1.5))
                reset()
            } else {
                // Queue for later sending
                currentPhase = .savedLocally
                article.status = .savedLocally
                queueVM.enqueue(
                    epubData: result.epubData,
                    filename: result.filename,
                    article: article,
                    modelContext: modelContext
                )
                statusMessage = loc(.queuedArticle, result.content.title.truncated(to: 40))
                toast?.showQueued(loc(.phaseSavedLocally), subtitle: result.content.title.truncated(to: 50))

                DebugLogger.log(
                    "Conversion complete + queued: '\(result.content.title)' (\(result.filename))",
                    level: .info, category: .conversion
                )

                // Auto-reset after delay so the button reverts to idle
                try? await Task.sleep(for: .seconds(1.5))
                reset()
            }

        } catch {
            currentPhase = .failed
            article.status = .failed
            article.errorMessage = error.localizedDescription
            lastError = error.localizedDescription
            statusMessage = ""
            toast?.showError(loc(.phaseFailed), subtitle: error.localizedDescription)

            DebugLogger.log(
                "Conversion failed for \(url.absoluteString): \(error.localizedDescription)",
                level: .error, category: .conversion
            )
        }

        isProcessing = false
    }

    /// Convert only (no send) — generates EPUB for local save.
    func convertOnly(modelContext: ModelContext, settings: DeviceSettings? = nil) async -> Data? {
        guard let url = validatedURL else {
            lastError = loc(.enterValidURL)
            return nil
        }

        isProcessing = true
        lastError = nil

        let article = Article(url: url.absoluteString, sourceDomain: url.host ?? "unknown")
        modelContext.insert(article)

        do {
            let result = try await runConversion(url: url, article: article, settings: settings)

            lastEPUBData = result.epubData
            lastFilename = result.filename

            currentPhase = .savedLocally
            article.status = .savedLocally
            statusMessage = loc(.epubCreated, result.content.title.truncated(to: 40))

            isProcessing = false
            return result.epubData

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
        modelContext: ModelContext,
        toast: ToastManager? = nil
    ) async {
        guard deviceVM.isConnected else {
            lastError = loc(.x4NotConnected)
            return
        }

        isProcessing = true
        lastError = nil

        guard let url = URL(string: article.url) else {
            lastError = loc(.invalidArticleURL)
            isProcessing = false
            return
        }

        do {
            // Re-generate the EPUB
            let result = try await runConversion(url: url, article: article, settings: settings)

            currentPhase = .sending
            article.status = .sending
            let folder = settings?.convertFolder ?? "content"
            let uploadData = await EPUBOptimizer.optimizeIfNeeded(
                result.epubData,
                filename: result.filename,
                enabled: settings?.optimizeEPUBUpload ?? true
            )
            try await deviceVM.upload(data: uploadData, filename: result.filename, toFolder: folder)

            currentPhase = .sent
            article.status = .sent
            statusMessage = loc(.resentArticleToX4, result.content.title.truncated(to: 40))
            toast?.showSuccess(loc(.phaseSent), subtitle: result.content.title.truncated(to: 50))

            if ReviewPromptManager.shouldPromptAfterSuccess() {
                shouldRequestReview = true
            }

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
        modelContext: ModelContext,
        settings: DeviceSettings? = nil
    ) async -> (data: Data, filename: String)? {
        guard let url = URL(string: article.url) else {
            lastError = loc(.invalidArticleURL)
            return nil
        }

        isProcessing = true
        lastError = nil

        do {
            let result = try await runConversion(url: url, article: article, settings: settings)

            lastEPUBData = result.epubData
            lastFilename = result.filename

            currentPhase = .savedLocally
            article.status = .savedLocally
            isProcessing = false
            return (result.epubData, result.filename)

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

    /// Run the shared pipeline, mirroring phases onto this view model and the
    /// Article record, and updating the article's metadata on success.
    private func runConversion(
        url: URL,
        article: Article,
        settings: DeviceSettings?
    ) async throws -> ConversionResult {
        let options = ConversionOptions()
        let result = try await conversionService.convert(url: url, options: options) { phase in
            currentPhase = phase
            article.status = phase
        }

        article.title = result.content.title
        article.author = result.content.author
        article.sourceDomain = result.finalURL.host ?? url.host ?? "unknown"

        return result
    }
}
