import SwiftUI
import SwiftData

/// Displays article conversion history with tap actions, share, resend, and delete.
struct HistoryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Article.createdAt, order: .reverse) private var articles: [Article]

    var historyVM: HistoryViewModel
    var convertVM: ConvertViewModel
    var deviceVM: DeviceViewModel
    var settings: DeviceSettings

    @State private var selectedArticle: Article?
    @State private var showShareSheet = false
    @State private var shareEPUBData: Data?
    @State private var shareFilename: String?
    @State private var showClearConfirmation = false

    var body: some View {
        NavigationStack {
            Group {
                if articles.isEmpty {
                    emptyState
                } else {
                    articleList
                }
            }
            .navigationTitle("History")
            .settingsToolbar(deviceVM: deviceVM, settings: settings)
            .toolbar {
                if !articles.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Clear All", role: .destructive) {
                            showClearConfirmation = true
                        }
                        .font(.footnote)
                    }
                }
            }
            .alert("Clear All Articles?", isPresented: $showClearConfirmation) {
                Button("Delete All", role: .destructive) {
                    historyVM.clearAll(modelContext: modelContext)
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will permanently delete all \(articles.count) articles from your history.")
            }
            .confirmationDialog(
                selectedArticle?.title ?? "Article",
                isPresented: .init(
                    get: { selectedArticle != nil },
                    set: { if !$0 { selectedArticle = nil } }
                ),
                titleVisibility: .visible
            ) {
                if let article = selectedArticle {
                    Button("Reconvert & Share") {
                        let target = article
                        Task {
                            if let result = await convertVM.reconvertForShare(
                                article: target,
                                modelContext: modelContext
                            ) {
                                shareEPUBData = result.data
                                shareFilename = result.filename
                                showShareSheet = true
                            }
                        }
                    }

                    if deviceVM.isConnected {
                        Button("Resend to X4") {
                            let target = article
                            Task {
                                await convertVM.resend(
                                    article: target,
                                    deviceVM: deviceVM,
                                    settings: settings,
                                    modelContext: modelContext
                                )
                            }
                        }
                    }

                    Button("Copy URL") {
                        UIPasteboard.general.string = article.url
                    }

                    Button("Cancel", role: .cancel) {}
                }
            }
            .sheet(isPresented: $showShareSheet) {
                if let data = shareEPUBData, let filename = shareFilename {
                    let tempURL = FileManager.default.temporaryDirectory
                        .appendingPathComponent(filename)
                    ShareSheetView(items: [tempURL], epubData: data, filename: filename)
                }
            }
        }
    }

    // MARK: - Article List

    private var articleList: some View {
        List {
            ForEach(articles) { article in
                articleRow(article)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selectedArticle = article
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            historyVM.delete(article: article, from: modelContext)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                    .swipeActions(edge: .leading, allowsFullSwipe: true) {
                        if deviceVM.isConnected {
                            Button {
                                Task {
                                    await convertVM.resend(
                                        article: article,
                                        deviceVM: deviceVM,
                                        settings: settings,
                                        modelContext: modelContext
                                    )
                                }
                            } label: {
                                Label("Resend", systemImage: "paperplane")
                            }
                            .tint(.blue)
                        }
                    }
            }
        }
    }

    // MARK: - Article Row

    private func articleRow(_ article: Article) -> some View {
        HStack(spacing: 12) {
            // Status icon
            statusIcon(for: article.status)

            VStack(alignment: .leading, spacing: 4) {
                Text(article.title.isEmpty ? "Untitled" : article.title)
                    .font(.body.weight(.medium))
                    .lineLimit(2)

                HStack(spacing: 6) {
                    Text(article.sourceDomain)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text("·")
                        .foregroundStyle(.tertiary)

                    Text(article.createdAt, format: .relative(presentation: .named))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let error = article.errorMessage, article.status == .failed {
                    Text(error)
                        .font(.caption2)
                        .foregroundStyle(.red)
                        .lineLimit(1)
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }

    private func statusIcon(for status: ConversionStatus) -> some View {
        Group {
            switch status {
            case .sent:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            case .savedLocally:
                Image(systemName: "arrow.down.circle.fill")
                    .foregroundStyle(.blue)
            case .failed:
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundStyle(.red)
            case .pending, .fetching, .extracting, .building, .sending:
                ProgressView()
                    .controlSize(.small)
            }
        }
        .frame(width: 28)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Articles Yet", systemImage: "doc.text")
        } description: {
            Text("Convert a web page to EPUB and it will appear here.")
        }
    }
}
