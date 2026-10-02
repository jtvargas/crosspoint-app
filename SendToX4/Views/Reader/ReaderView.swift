import SwiftUI
import SwiftData

/// Full-screen Apple News-style reader for a local EPUB.
///
/// Content streams lazily from the zip via `EPUBSchemeHandler`; article-backed
/// reading progress persists and restores on reopen. File-only reads do not save progress.
struct ReaderView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    private let article: Article?
    private let standaloneFileURL: URL?
    private let standaloneTitle: String

    init(article: Article) {
        self.article = article
        self.standaloneFileURL = nil
        self.standaloneTitle = ""
    }

    init(fileURL: URL, title: String) {
        self.article = nil
        self.standaloneFileURL = fileURL
        self.standaloneTitle = title
    }

    private var title: String {
        article?.title ?? standaloneTitle
    }

    private var fileURL: URL? {
        if let article {
            return LibraryStore.epubURL(for: article)
        }
        return standaloneFileURL
    }

    @AppStorage("readerFontScale") private var fontScale = 1.0

    @State private var document: EPUBDocument?
    @State private var loadFailed = false
    @State private var chapterAnchor: String?
    @State private var pendingProgress: Double?
    @State private var progressSaveTask: Task<Void, Never>?

    private static let fontScaleRange = 0.75...1.6
    private static let fontScaleStep = 0.1

    var body: some View {
        NavigationStack {
            Group {
                if let document {
                    ReaderWebView(
                        document: document,
                        fontScale: fontScale,
                        chapterAnchor: $chapterAnchor,
                        initialProgress: article?.readingProgress ?? 0,
                        onProgress: scheduleProgressSave
                    )
                    .ignoresSafeArea(edges: .bottom)
                } else if loadFailed {
                    ContentUnavailableView(
                        loc(.readerCouldNotOpen),
                        systemImage: "book.closed",
                        description: Text(loc(.readerCouldNotOpenDescription))
                    )
                } else {
                    ProgressView()
                }
            }
            .navigationTitle(title.isEmpty ? loc(.untitled) : title)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(loc(.done)) {
                        flushProgressSave()
                        dismiss()
                    }
                }

                if let document, document.spine.count > 1 {
                    ToolbarItem(placement: .secondaryAction) {
                        Menu {
                            ForEach(document.spine) { item in
                                Button(item.title) {
                                    chapterAnchor = item.anchor
                                }
                            }
                        } label: {
                            Label(loc(.readerChapters), systemImage: "list.bullet")
                        }
                    }
                }

                ToolbarItem(placement: .secondaryAction) {
                    Menu {
                        Button {
                            fontScale = min(Self.fontScaleRange.upperBound, fontScale + Self.fontScaleStep)
                        } label: {
                            Label(loc(.readerLargerText), systemImage: "textformat.size.larger")
                        }
                        .disabled(fontScale >= Self.fontScaleRange.upperBound)

                        Button {
                            fontScale = max(Self.fontScaleRange.lowerBound, fontScale - Self.fontScaleStep)
                        } label: {
                            Label(loc(.readerSmallerText), systemImage: "textformat.size.smaller")
                        }
                        .disabled(fontScale <= Self.fontScaleRange.lowerBound)

                        Button {
                            fontScale = 1.0
                        } label: {
                            Label(loc(.readerResetTextSize), systemImage: "textformat.size")
                        }
                    } label: {
                        Label(loc(.readerTextSize), systemImage: "textformat.size")
                    }
                }

                if let fileURL {
                    ToolbarItem(placement: .secondaryAction) {
                        ShareLink(item: fileURL) {
                            Label(loc(.reconvertAndShare), systemImage: "square.and.arrow.up")
                        }
                    }
                }
            }
            .task {
                openDocument()
            }
            .onDisappear {
                flushProgressSave()
            }
        }
    }

    // MARK: - Document

    private func openDocument() {
        guard document == nil else { return }
        guard let fileURL else {
            loadFailed = true
            return
        }
        do {
            document = try EPUBDocument(fileURL: fileURL)
        } catch {
            DebugLogger.log(
                "Reader failed to open EPUB: \(error.localizedDescription)",
                level: .error, category: .conversion
            )
            loadFailed = true
        }
    }

    // MARK: - Progress Persistence (throttled)

    private func scheduleProgressSave(_ progress: Double) {
        guard let article else { return }
        pendingProgress = progress
        guard progressSaveTask == nil else { return }
        progressSaveTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(600))
            progressSaveTask = nil
            if let value = pendingProgress {
                article.readingProgress = value
            }
        }
    }

    private func flushProgressSave() {
        guard let article else { return }
        progressSaveTask?.cancel()
        progressSaveTask = nil
        if let value = pendingProgress {
            article.readingProgress = value
        }
    }
}
