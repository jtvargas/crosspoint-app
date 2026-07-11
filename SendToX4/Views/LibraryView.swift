import SwiftUI
import SwiftData

/// Library tab: locally saved article EPUBs, readable in the in-app reader.
struct LibraryView: View {
    @Environment(\.modelContext) private var modelContext

    var toast: ToastManager

    /// Articles with a persisted library EPUB, newest first.
    @Query(
        filter: #Predicate<Article> { $0.libraryFilePath != nil },
        sort: \Article.createdAt,
        order: .reverse
    ) private var articles: [Article]

    @State private var searchText = ""
    @State private var readerArticle: Article?

    private var filteredArticles: [Article] {
        guard !searchText.isEmpty else { return articles }
        let query = searchText.lowercased()
        return articles.filter {
            $0.title.lowercased().contains(query)
                || $0.sourceDomain.lowercased().contains(query)
                || ($0.author?.lowercased().contains(query) ?? false)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if articles.isEmpty {
                    emptyState
                } else {
                    articleList
                }
            }
            .navigationTitle(loc(.tabLibrary))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .searchable(text: $searchText, prompt: loc(.librarySearchPrompt))
            #if os(iOS)
            .fullScreenCover(item: $readerArticle) { article in
                ReaderView(article: article)
            }
            #else
            .sheet(item: $readerArticle) { article in
                ReaderView(article: article)
                    .frame(minWidth: 700, minHeight: 800)
            }
            #endif
        }
    }

    // MARK: - List

    private var articleList: some View {
        List {
            ForEach(filteredArticles) { article in
                Button {
                    readerArticle = article
                } label: {
                    libraryRow(article)
                }
                .buttonStyle(.plain)
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        removeFromLibrary(article)
                    } label: {
                        Label(loc(.libraryRemove), systemImage: "trash")
                    }
                }
                .contextMenu {
                    Button {
                        readerArticle = article
                    } label: {
                        Label(loc(.libraryRead), systemImage: "book")
                    }
                    if let fileURL = LibraryStore.epubURL(for: article) {
                        ShareLink(item: fileURL) {
                            Label(loc(.reconvertAndShare), systemImage: "square.and.arrow.up")
                        }
                    }
                    Button {
                        ClipboardHelper.copy(article.url)
                        toast.showCopied(loc(.toastURLCopied))
                    } label: {
                        Label(loc(.copyURL), systemImage: "doc.on.doc")
                    }
                    Divider()
                    Button(role: .destructive) {
                        removeFromLibrary(article)
                    } label: {
                        Label(loc(.libraryRemove), systemImage: "trash")
                    }
                }
            }
        }
        #if os(iOS)
        .listStyle(.insetGrouped)
        #else
        .listStyle(.inset)
        #endif
    }

    private func libraryRow(_ article: Article) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "book.closed.fill")
                .font(.title3)
                .foregroundStyle(AppColor.accent)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 4) {
                Text(article.title.isEmpty ? loc(.untitled) : article.title)
                    .font(.body.weight(.medium))
                    .lineLimit(2)

                HStack(spacing: 6) {
                    if let author = article.author, !author.isEmpty {
                        Text(author)
                            .lineLimit(1)
                        Text("\u{00B7}")
                            .foregroundStyle(.tertiary)
                    }
                    Text(article.sourceDomain)
                        .lineLimit(1)
                    Text("\u{00B7}")
                        .foregroundStyle(.tertiary)
                    Text(article.createdAt, format: .relative(presentation: .named))
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    if let size = article.epubFileSize {
                        Text(StorageCalculator.formatted(size))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    if let progress = article.readingProgress, progress > 0.01 {
                        ProgressView(value: min(progress, 1.0))
                            .progressViewStyle(.linear)
                            .frame(maxWidth: 80)
                            .tint(AppColor.accent)
                        if progress >= 0.98 {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.caption2)
                                .foregroundStyle(AppColor.success)
                        }
                    }
                }
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    // MARK: - Empty State

    private var emptyState: some View {
        ContentUnavailableView {
            Label(loc(.libraryEmptyTitle), systemImage: "books.vertical")
        } description: {
            Text(loc(.libraryEmptyDescription))
        }
    }

    // MARK: - Actions

    /// Removes only the local EPUB copy — the article stays in History.
    private func removeFromLibrary(_ article: Article) {
        LibraryStore.delete(for: article)
    }
}
