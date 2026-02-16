import SwiftUI
import SwiftData

/// Main RSS feed sheet — browse articles, select, and batch send/queue.
struct RSSFeedSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    var rssVM: RSSFeedViewModel
    var deviceVM: DeviceViewModel
    var queueVM: QueueViewModel
    var settings: DeviceSettings

    @State private var showConfig = false

    private var feeds: [RSSFeed] {
        rssVM.fetchFeeds(modelContext: modelContext)
    }

    private var articles: [RSSArticle] {
        rssVM.fetchFilteredArticles(modelContext: modelContext)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if feeds.isEmpty {
                    emptyState
                } else {
                    VStack(spacing: 0) {
                        feedSelector
                        articleList
                    }
                }

                // Batch action bar (sticky bottom)
                if !rssVM.selectedArticleIDs.isEmpty || rssVM.isBatchProcessing {
                    batchActionBar
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

    // MARK: - Feed Selector

    private var feedSelector: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                feedPill(title: loc(.filterAll), feedID: nil, count: totalNewCount)

                ForEach(feeds) { feed in
                    feedPill(
                        title: feed.title,
                        feedID: feed.id,
                        count: newCount(for: feed.id)
                    )
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
        }
    }

    private func feedPill(title: String, feedID: UUID?, count: Int) -> some View {
        let isSelected = rssVM.selectedFeedID == feedID
        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                rssVM.selectedFeedID = feedID
                rssVM.deselectAll()
            }
        } label: {
            HStack(spacing: 4) {
                Text(title)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)

                if count > 0 {
                    Text("\(count)")
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(
                            isSelected ? Color.white.opacity(0.3) : AppColor.accent.opacity(0.2),
                            in: Capsule()
                        )
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                isSelected ? AppColor.accent : Color.clear,
                in: Capsule()
            )
            .foregroundStyle(isSelected ? .white : .primary)
            .overlay(
                Capsule()
                    .stroke(isSelected ? Color.clear : Color.secondary.opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
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

                        if isProcessed {
                            statusBadge(for: article.status)
                        }
                    }
                    .padding(.top, 2)
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
