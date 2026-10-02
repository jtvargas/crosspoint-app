import Foundation
import SwiftData

/// Prepares a local book, then commits its library and queue copies together.
@MainActor
@Observable
final class FileImportViewModel {
    private(set) var isProcessing = false
    private(set) var completedPages = 0
    private(set) var totalPages = 0
    private(set) var filename = ""
    private(set) var importedTitle: String?
    private(set) var errorMessage: String?

    var isSuccess: Bool { importedTitle != nil }

    func reset() {
        guard !isProcessing else { return }
        completedPages = 0
        totalPages = 0
        filename = ""
        importedTitle = nil
        errorMessage = nil
    }

    func importFile(at url: URL, modelContext: ModelContext) async {
        guard !isProcessing else { return }
        reset()
        filename = url.lastPathComponent
        isProcessing = true
        defer { isProcessing = false }

        do {
            let prepared = try await FileImportService.prepare(url: url) { completed, total in
                await self.updateProgress(completed: completed, total: total)
            }
            try Task.checkCancellation()
            try persist(prepared, modelContext: modelContext)
            importedTitle = prepared.title
        } catch is CancellationError {
            // The sheet task owns preparation; cancellation must never enqueue a book.
        } catch let error as FileImportError {
            errorMessage = message(for: error)
        } catch {
            errorMessage = loc(.importSaveFailed)
        }
    }

    private func updateProgress(completed: Int, total: Int) {
        completedPages = completed
        totalPages = total
    }

    private func persist(_ prepared: PreparedImport, modelContext: ModelContext) throws {
        // A dedicated context makes rollback local to this import, not any concurrent UI edits.
        let context = ModelContext(modelContext.container)
        context.autosaveEnabled = false
        let article = Article(
            url: "",
            title: prepared.title,
            author: prepared.author.isEmpty ? nil : prepared.author,
            sourceDomain: loc(.importLocalFile)
        )
        // A durable local identity, never a stale security-scoped provider URL.
        article.url = "crossx-import://local/\(article.id.uuidString)"
        article.status = .savedLocally
        context.insert(article)
        var queuedItem: QueueItem?
        do {
            try LibraryStore.save(epubData: prepared.epubData, for: article)
            queuedItem = try QueueViewModel.enqueueEPUB(
                epubData: prepared.epubData,
                filename: prepared.filename,
                article: article,
                modelContext: context
            )
            try context.save()
        } catch {
            if let queuedItem {
                try? FileManager.default.removeItem(at: queuedItem.fileURL)
            }
            LibraryStore.delete(for: article)
            context.rollback()
            throw error
        }
    }

    private func message(for error: FileImportError) -> String {
        switch error {
        case .unsupportedType: loc(.importUnsupportedType)
        case .unreadableFile: loc(.importUnreadableFile)
        case .invalidEPUB: loc(.importInvalidEPUB)
        case .invalidPDF: loc(.importInvalidPDF)
        case .lockedPDF: loc(.importLockedPDF)
        case .emptyPDF: loc(.importEmptyPDF)
        case .pageFailed(let page): loc(.importPageFailed, page)
        case .buildFailed: loc(.importBuildFailed)
        }
    }
}
