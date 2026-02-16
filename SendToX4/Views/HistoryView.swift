import SwiftUI
import SwiftData

// MARK: - Filter

/// Controls which history items are visible.
private enum HistoryFilter: String, CaseIterable {
    case all = "All"
    case conversions = "Conversions"
    case fileActivity = "File Activity"
    case queueActivity = "Queue"
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

    @State private var showShareSheet = false
    @State private var shareEPUBData: Data?
    @State private var shareFilename: String?
    @State private var showClearConfirmation = false
    @State private var filter: HistoryFilter = .all
    @State private var expandedItems: Set<String> = []

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
            items += activities.filter { $0.category != .queue }.map { .activity($0) }
        case .queueActivity:
            items += activities.filter { $0.category == .queue }.map { .activity($0) }
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
                    ToolbarItem(placement: .navigation) {
                        filterMenu
                    }
                }

                // Clear menu
                if !isEmpty {
                    ToolbarItem(placement: .primaryAction) {
                        clearMenu
                    }
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
                    conversionRow(article, itemID: item.id)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            withAnimation(.spring(duration: 0.3)) {
                                toggleExpanded(item.id)
                            }
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
                                .tint(AppColor.accent)
                            }
                        }

                case .activity(let event):
                    activityRow(event, itemID: item.id)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            withAnimation(.spring(duration: 0.3)) {
                                toggleExpanded(item.id)
                            }
                        }
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

    // MARK: - Expand / Collapse

    private func toggleExpanded(_ id: String) {
        if expandedItems.contains(id) {
            expandedItems.remove(id)
        } else {
            expandedItems.insert(id)
        }
    }

    private func isExpanded(_ id: String) -> Bool {
        expandedItems.contains(id)
    }

    // MARK: - Conversion Row

    private func conversionRow(_ article: Article, itemID: String) -> some View {
        HStack(spacing: 12) {
            conversionStatusIcon(for: article.status)

            VStack(alignment: .leading, spacing: 4) {
                Text(article.title.isEmpty ? "Untitled" : article.title)
                    .font(.body.weight(.medium))
                    .lineLimit(isExpanded(itemID) ? nil : 2)

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
                        .foregroundStyle(AppColor.error)
                        .lineLimit(isExpanded(itemID) ? nil : 1)
                }
            }

            Spacer()

            // Ellipsis menu for actions
            conversionMenu(for: article)
        }
        .padding(.vertical, 4)
    }

    private func conversionMenu(for article: Article) -> some View {
        Menu {
            Button {
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
            } label: {
                Label("Reconvert & Share", systemImage: "square.and.arrow.up")
            }

            if deviceVM.isConnected {
                Button {
                    let target = article
                    Task {
                        await convertVM.resend(
                            article: target,
                            deviceVM: deviceVM,
                            settings: settings,
                            modelContext: modelContext
                        )
                    }
                } label: {
                    Label("Resend to X4", systemImage: "paperplane")
                }
            }

            Button {
                ClipboardHelper.copy(article.url)
            } label: {
                Label("Copy URL", systemImage: "doc.on.doc")
            }

            Divider()

            Button(role: .destructive) {
                historyVM.delete(article: article, from: modelContext)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.body)
                .foregroundStyle(.secondary)
        }
    }

    private func conversionStatusIcon(for status: ConversionStatus) -> some View {
        Group {
            switch status {
            case .sent:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(AppColor.success)
            case .savedLocally:
                Image(systemName: "arrow.down.circle.fill")
                    .foregroundStyle(AppColor.accent)
            case .failed:
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundStyle(AppColor.error)
            case .pending, .fetching, .extracting, .building, .sending:
                ProgressView()
                    .controlSize(.small)
            }
        }
        .frame(width: 28)
    }

    // MARK: - Activity Row

    private func activityRow(_ event: ActivityEvent, itemID: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: event.iconName)
                .foregroundStyle(event.status == .failed ? AppColor.error : AppColor.accent)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 4) {
                Text(event.actionLabel)
                    .font(.body.weight(.medium))

                Text(event.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(isExpanded(itemID) ? nil : 2)

                HStack(spacing: 6) {
                    Text(event.categoryLabel)
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
                        .foregroundStyle(AppColor.error)
                        .lineLimit(isExpanded(itemID) ? nil : 1)
                }
            }

            Spacer()
        }
        .padding(.vertical, 4)
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
            case .queueActivity:
                Text("No queue activity. Queued EPUBs sent to the device will appear here.")
            }
        }
    }
}
