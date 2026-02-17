import SwiftUI
import SwiftData

/// Main RSS feed sheet — two-level navigation:
/// 1. Feed grid (2×2 cards) as the landing page.
/// 2. Article list for a selected feed (or all feeds combined).
struct RSSFeedSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    var rssVM: RSSFeedViewModel
    var deviceVM: DeviceViewModel
    var queueVM: QueueViewModel
    var settings: DeviceSettings

    private var feeds: [RSSFeed] {
        rssVM.fetchFeeds(modelContext: modelContext)
    }

    var body: some View {
        NavigationStack {
            Group {
                if feeds.isEmpty {
                    emptyState
                } else {
                    feedGrid
                }
            }
            .navigationTitle(loc(.rssFeeds))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(loc(.done)) {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    NavigationLink {
                        RSSFeedConfigView(rssVM: rssVM)
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
            }
            .refreshable {
                await rssVM.refreshAllFeeds(modelContext: modelContext)
            }
            .onAppear {
                rssVM.updateNewArticleCount(modelContext: modelContext)
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "dot.radiowaves.up.and.down")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)

            Text(loc(.rssNoFeedsTitle))
                .font(.title3.weight(.semibold))
                .foregroundStyle(.secondary)

            Text(loc(.rssNoFeedsDescription))
                .font(.subheadline)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            NavigationLink {
                RSSFeedConfigView(rssVM: rssVM)
            } label: {
                HStack {
                    Image(systemName: "plus.circle.fill")
                    Text(loc(.rssAddFirstFeed))
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)

            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Feed Grid

    private var feedGrid: some View {
        ScrollView {
            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
                spacing: 12
            ) {
                // "All Feeds" card (first position)
                allFeedsCard

                // Per-feed cards
                ForEach(feeds) { feed in
                    feedCard(for: feed)
                }

                // "+ Add Feed" card (last position)
                addFeedCard
            }
            .padding()
        }
    }

    // MARK: - All Feeds Card

    private var allFeedsCard: some View {
        NavigationLink {
            RSSArticleListView(
                rssVM: rssVM,
                deviceVM: deviceVM,
                queueVM: queueVM,
                settings: settings,
                feedTitle: loc(.rssAllFeeds),
                feedID: nil
            )
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "rectangle.stack.fill")
                        .font(.title3)
                        .foregroundStyle(AppColor.accent)
                    Spacer()
                    if totalNewCount > 0 {
                        Text("\(totalNewCount)")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(AppColor.accent, in: Capsule())
                    }
                }

                Spacer()

                Text(loc(.rssAllFeeds))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(loc(.rssFeedCount, feeds.count))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .aspectRatio(1.0, contentMode: .fill)
            .contentShape(Rectangle())
            .glassEffect(.regular, in: .rect(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Feed Card

    private func feedCard(for feed: RSSFeed) -> some View {
        let count = newCount(for: feed.id)

        return NavigationLink {
            RSSArticleListView(
                rssVM: rssVM,
                deviceVM: deviceVM,
                queueVM: queueVM,
                settings: settings,
                feedTitle: feed.title,
                feedID: feed.id
            )
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "dot.radiowaves.up.and.down")
                        .font(.title3)
                        .foregroundStyle(feed.isEnabled ? AppColor.accent : .secondary)
                    Spacer()
                    if count > 0 {
                        Text("\(count)")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(AppColor.accent, in: Capsule())
                    }
                }

                Spacer()

                Text(feed.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(feed.domain)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .aspectRatio(1.0, contentMode: .fill)
            .contentShape(Rectangle())
            .glassEffect(.regular, in: .rect(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Add Feed Card

    private var addFeedCard: some View {
        NavigationLink {
            RSSFeedConfigView(rssVM: rssVM)
        } label: {
            VStack(spacing: 8) {
                Image(systemName: "plus")
                    .font(.title2.weight(.medium))
                    .foregroundStyle(.secondary)

                Text(loc(.rssAddNewFeed))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .aspectRatio(1.0, contentMode: .fill)
            .contentShape(Rectangle())
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                    .foregroundStyle(Color.secondary.opacity(0.3))
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers

    private var totalNewCount: Int {
        let newStatus = RSSArticleStatus.new.rawValue
        let descriptor = FetchDescriptor<RSSArticle>(
            predicate: #Predicate<RSSArticle> { $0.statusRaw == newStatus }
        )
        return (try? modelContext.fetchCount(descriptor)) ?? 0
    }

    private func newCount(for feedID: UUID) -> Int {
        let newStatus = RSSArticleStatus.new.rawValue
        let descriptor = FetchDescriptor<RSSArticle>(
            predicate: #Predicate<RSSArticle> { $0.feedID == feedID && $0.statusRaw == newStatus }
        )
        return (try? modelContext.fetchCount(descriptor)) ?? 0
    }
}

// MARK: - Article List View (Level 2)

/// Displays articles for a single feed or all feeds combined.
/// Pushed onto the NavigationStack from the feed grid.
private struct RSSArticleListView: View {
    @Environment(\.modelContext) private var modelContext
    var rssVM: RSSFeedViewModel
    var deviceVM: DeviceViewModel
    var queueVM: QueueViewModel
    var settings: DeviceSettings

    /// Display title for the navigation bar.
    let feedTitle: String

    /// Feed to filter by. `nil` means show all feeds.
    let feedID: UUID?

    private var articles: [RSSArticle] {
        rssVM.fetchFilteredArticles(modelContext: modelContext)
    }

    var body: some View {
        VStack(spacing: 0) {
            articleList

            // Batch action bar (sticky bottom)
            if !rssVM.selectedArticleIDs.isEmpty || rssVM.isBatchProcessing {
                batchActionBar
            }
        }
        .navigationTitle(feedTitle)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .onAppear {
            rssVM.selectedFeedID = feedID
            rssVM.deselectAll()
        }
    }

    // MARK: - Article List

    private var articleList: some View {
        List {
            // Selection header
            if !articles.isEmpty {
                Section {
                    HStack {
                        let selectableCount = articles.filter { $0.status == .new }.count
                        if rssVM.selectedArticleIDs.count == selectableCount && selectableCount > 0 {
                            Button(loc(.rssDeselectAll)) {
                                rssVM.deselectAll()
                            }
                            .font(.caption.weight(.medium))
                        } else {
                            Button(loc(.rssSelectAllNew)) {
                                rssVM.selectAllNew(modelContext: modelContext)
                            }
                            .font(.caption.weight(.medium))
                            .disabled(selectableCount == 0)
                        }

                        Spacer()

                        if !rssVM.selectedArticleIDs.isEmpty {
                            Text(loc(.rssSelectedCount, rssVM.selectedArticleIDs.count))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            // Articles
            Section {
                if articles.isEmpty {
                    noArticlesView
                } else {
                    ForEach(articles) { article in
                        articleRow(article)
                    }
                }
            }

            // Success message
            if let success = rssVM.successMessage {
                Section {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(AppColor.success)
                        Text(success)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            // Error message
            if let error = rssVM.errorMessage, rssVM.isBatchProcessing == false {
                Section {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(AppColor.error)
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
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

    private var noArticlesView: some View {
        VStack(spacing: 8) {
            Image(systemName: "newspaper")
                .font(.title3)
                .foregroundStyle(.tertiary)
            Text(loc(.rssNoArticles))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    // MARK: - Article Row

    private func articleRow(_ article: RSSArticle) -> some View {
        let isProcessed = article.status == .sent || article.status == .queued
        let isFailed = article.status == .failed
        let isSelected = rssVM.selectedArticleIDs.contains(article.id)

        return Button {
            if !isProcessed {
                rssVM.toggleSelection(article.id)
            }
        } label: {
            HStack(alignment: .top, spacing: 12) {
                // Selection indicator
                selectionIcon(isSelected: isSelected, status: article.status)
                    .frame(width: 22)
                    .padding(.top, 2)

                VStack(alignment: .leading, spacing: 4) {
                    // Title
                    Text(article.title)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(2)
                        .foregroundStyle(isProcessed ? .secondary : .primary)

                    // Author + date
                    HStack(spacing: 4) {
                        if let author = article.author {
                            Text(author)
                            Text("\u{00B7}")
                        }
                        if let date = article.publishedAt {
                            Text(date, format: .relative(presentation: .named))
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.tertiary)

                    // Summary
                    if let summary = article.summary, !summary.isEmpty {
                        Text(summary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }

                    // Domain + status
                    HStack(spacing: 6) {
                        Text(article.domain)
                            .font(.caption2.weight(.medium))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.1), in: Capsule())

                        if isProcessed || isFailed {
                            statusBadge(for: article.status)
                        }
                    }
                    .padding(.top, 2)

                    // Error message for failed articles
                    if isFailed, let errorMsg = article.errorMessage {
                        Text(errorMsg)
                            .font(.caption2)
                            .foregroundStyle(AppColor.error)
                            .lineLimit(2)
                    }
                }
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
        .opacity(isProcessed ? 0.6 : 1.0)
    }

    @ViewBuilder
    private func selectionIcon(isSelected: Bool, status: RSSArticleStatus) -> some View {
        switch status {
        case .sent:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(AppColor.success)
        case .queued:
            Image(systemName: "clock.fill")
                .foregroundStyle(AppColor.warning)
        case .failed:
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(AppColor.error)
        case .new:
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isSelected ? AppColor.accent : .secondary)
        }
    }

    @ViewBuilder
    private func statusBadge(for status: RSSArticleStatus) -> some View {
        switch status {
        case .sent:
            HStack(spacing: 2) {
                Image(systemName: "checkmark")
                Text(loc(.rssSent))
            }
            .font(.caption2.weight(.medium))
            .foregroundStyle(AppColor.success)
        case .queued:
            HStack(spacing: 2) {
                Image(systemName: "clock")
                Text(loc(.rssQueued))
            }
            .font(.caption2.weight(.medium))
            .foregroundStyle(AppColor.warning)
        case .failed:
            HStack(spacing: 2) {
                Image(systemName: "xmark")
                Text(loc(.rssFailed))
            }
            .font(.caption2.weight(.medium))
            .foregroundStyle(AppColor.error)
        case .new:
            EmptyView()
        }
    }

    // MARK: - Batch Action Bar

    private var batchActionBar: some View {
        VStack(spacing: 8) {
            Divider()

            if rssVM.isBatchProcessing, let progress = rssVM.batchProgress {
                HStack {
                    ProgressView(value: Double(progress.current), total: Double(progress.total))
                    Text(loc(.rssConverting, progress.current, progress.total))
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                .padding(.horizontal)
            } else {
                HStack {
                    Text(loc(.rssSelectedCount, rssVM.selectedArticleIDs.count))
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)

                    Spacer()

                    Button {
                        Task {
                            await rssVM.sendSelected(
                                deviceVM: deviceVM,
                                queueVM: queueVM,
                                settings: settings,
                                modelContext: modelContext
                            )
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: deviceVM.isConnected
                                  ? "paperplane.fill" : "tray.and.arrow.down.fill")
                            Text(deviceVM.isConnected
                                 ? loc(.rssConvertAndSend, rssVM.selectedArticleIDs.count)
                                 : loc(.rssConvertAndQueue, rssVM.selectedArticleIDs.count))
                        }
                        .font(.subheadline.weight(.semibold))
                    }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.capsule)
                    .disabled(rssVM.isBatchProcessing)
                }
                .padding(.horizontal)
            }
        }
        .padding(.bottom, 8)
        .background(.bar)
    }
}
