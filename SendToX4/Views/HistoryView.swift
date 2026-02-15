import SwiftUI
import SwiftData

// MARK: - Filter

/// Controls which history items are visible.
private enum HistoryFilter: String, CaseIterable {
    case all = "All"
    case conversions = "Conversions"
    case fileActivity = "File Activity"
}

// MARK: - Timeline Item

/// Normalized wrapper that unifies Article and ActivityEvent into a single timeline.
private enum TimelineItem: Identifiable {
    case conversion(Article)
    case activity(ActivityEvent)

    var id: String {
        switch self {
        case .conversion(let article): return "article-\(article.id.uuidString)"
        case .activity(let event):     return "activity-\(event.id.uuidString)"
        }
    }

    var date: Date {
        switch self {
        case .conversion(let article): return article.createdAt
        case .activity(let event):     return event.timestamp
        }
    }
}

// MARK: - HistoryView

/// Displays a unified activity timeline combining conversion history and file manager operations.
struct HistoryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Article.createdAt, order: .reverse) private var articles: [Article]
    @Query(sort: \ActivityEvent.timestamp, order: .reverse) private var activities: [ActivityEvent]

    var historyVM: HistoryViewModel
    var convertVM: ConvertViewModel
    var deviceVM: DeviceViewModel
    var settings: DeviceSettings

    @State private var selectedArticle: Article?
    @State private var showShareSheet = false
    @State private var shareEPUBData: Data?
    @State private var shareFilename: String?
    @State private var showClearConfirmation = false
    @State private var filter: HistoryFilter = .all

    // MARK: - Unified Timeline

    private var timeline: [TimelineItem] {
        var items: [TimelineItem] = []

        switch filter {
        case .all:
            items += articles.map { .conversion($0) }
            items += activities.map { .activity($0) }
        case .conversions:
            items += articles.map { .conversion($0) }
        case .fileActivity:
            items += activities.map { .activity($0) }
        }

        return items.sorted { $0.date > $1.date }
    }

    private var isEmpty: Bool {
        articles.isEmpty && activities.isEmpty
    }

    var body: some View {
        NavigationStack {
            Group {
                if isEmpty {
                    emptyState
                } else if timeline.isEmpty {
                    filteredEmptyState
                } else {
                    timelineList
                }
            }
            .navigationTitle("History")
            .settingsToolbar(deviceVM: deviceVM, settings: settings)
            .toolbar {
                // Filter menu
                if !isEmpty {
                    ToolbarItem(placement: .topBarLeading) {
                        filterMenu
                    }
                }

                // Clear menu
                if !isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        clearMenu
                    }
                }
            }
            // MARK: - Article Action Dialog
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
            // MARK: - Share Sheet
            .sheet(isPresented: $showShareSheet) {
                if let data = shareEPUBData, let filename = shareFilename {
                    let tempURL = FileManager.default.temporaryDirectory
                        .appendingPathComponent(filename)
                    ShareSheetView(items: [tempURL], epubData: data, filename: filename)
                }
            }
            // MARK: - Clear Confirmation
            .alert("Clear All History?", isPresented: $showClearConfirmation) {
                Button("Delete All", role: .destructive) {
                    historyVM.clearAll(modelContext: modelContext)
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will permanently delete all conversion history and file activity.")
            }
        }
    }

    // MARK: - Timeline List

    private var timelineList: some View {
        List {
            ForEach(timeline) { item in
                switch item {
                case .conversion(let article):
                    conversionRow(article)
                        .contentShape(Rectangle())
                        .onTapGesture { selectedArticle = article }
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

                case .activity(let event):
                    activityRow(event)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                historyVM.delete(activity: event, from: modelContext)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                }
            }
        }
    }

    // MARK: - Conversion Row (preserves existing design)

    private func conversionRow(_ article: Article) -> some View {
        HStack(spacing: 12) {
            conversionStatusIcon(for: article.status)

            VStack(alignment: .leading, spacing: 4) {
                Text(article.title.isEmpty ? "Untitled" : article.title)
                    .font(.body.weight(.medium))
                    .lineLimit(2)

                HStack(spacing: 6) {
                    Text(article.sourceDomain)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text("\u{00B7}")
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

    private func conversionStatusIcon(for status: ConversionStatus) -> some View {
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

    // MARK: - Activity Row

    private func activityRow(_ event: ActivityEvent) -> some View {
        HStack(spacing: 12) {
            activityIcon(for: event)

            VStack(alignment: .leading, spacing: 4) {
                Text(event.actionLabel)
                    .font(.body.weight(.medium))

                Text(event.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                HStack(spacing: 6) {
                    Text("File Manager")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)

                    Text("\u{00B7}")
                        .foregroundStyle(.tertiary)

                    Text(event.timestamp, format: .relative(presentation: .named))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                if let error = event.errorMessage {
                    Text(error)
                        .font(.caption2)
                        .foregroundStyle(.red)
                        .lineLimit(1)
                }
            }

            Spacer()
        }
        .padding(.vertical, 4)
    }

    private func activityIcon(for event: ActivityEvent) -> some View {
        Image(systemName: event.iconName)
            .foregroundStyle(activityColor(for: event))
            .frame(width: 28)
    }

    private func activityColor(for event: ActivityEvent) -> Color {
        if event.status == .failed { return .red }
        switch event.action {
        case .upload:       return .blue
        case .createFolder: return .yellow
        case .moveFile:     return .purple
        case .deleteFile:   return .orange
        case .deleteFolder: return .orange
        }
    }

    // MARK: - Filter Menu

    private var filterMenu: some View {
        Menu {
            ForEach(HistoryFilter.allCases, id: \.self) { option in
                Button {
                    withAnimation { filter = option }
                } label: {
                    if filter == option {
                        Label(option.rawValue, systemImage: "checkmark")
                    } else {
                        Text(option.rawValue)
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "line.3.horizontal.decrease.circle")
                if filter != .all {
                    Text(filter.rawValue)
                        .font(.caption)
                }
            }
        }
    }

    // MARK: - Clear Menu

    private var clearMenu: some View {
        Menu {
            Button("Clear All", role: .destructive) {
                showClearConfirmation = true
            }

            Divider()

            if !articles.isEmpty {
                Button("Clear Conversions", role: .destructive) {
                    historyVM.clearConversions(modelContext: modelContext)
                }
            }

            if !activities.isEmpty {
                Button("Clear File Activity", role: .destructive) {
                    historyVM.clearActivities(modelContext: modelContext)
                }
            }
        } label: {
            Text("Clear")
                .font(.footnote)
        }
    }

    // MARK: - Empty States

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Activity Yet", systemImage: "clock")
        } description: {
            Text("Convert a web page or manage files on your device to see your activity here.")
        }
    }

    private var filteredEmptyState: some View {
        ContentUnavailableView {
            Label("No \(filter.rawValue)", systemImage: "tray")
        } description: {
            switch filter {
            case .all:
                Text("No activity recorded yet.")
            case .conversions:
                Text("No conversion history. Convert a web page to EPUB to see it here.")
            case .fileActivity:
                Text("No file activity. Upload, move, or delete files to see activity here.")
            }
        }
    }
}
