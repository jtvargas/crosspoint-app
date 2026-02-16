import SwiftUI
import SwiftData

/// Feed management view — add, remove, and toggle RSS/Atom feeds.
struct RSSFeedConfigView: View {
    @Environment(\.modelContext) private var modelContext
    var rssVM: RSSFeedViewModel

    @State private var newFeedURL = ""

    private var feeds: [RSSFeed] {
        rssVM.fetchFeeds(modelContext: modelContext)
    }

    var body: some View {
        List {
            addFeedSection
            yourFeedsSection
        }
        .navigationTitle(loc(.rssManageFeeds))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    // MARK: - Add Feed Section

    private var addFeedSection: some View {
        Section {
            VStack(spacing: 12) {
                HStack {
                    Image(systemName: "link")
                        .foregroundStyle(.secondary)

                    TextField(loc(.rssEnterFeedURL), text: $newFeedURL)
                        #if os(iOS)
                        .textContentType(.URL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .submitLabel(.done)
                        #endif
                        .autocorrectionDisabled()
                        .onSubmit {
                            addFeed()
                        }

                    if !newFeedURL.isEmpty {
                        Button {
                            newFeedURL = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }

                Button {
                    addFeed()
                } label: {
                    HStack {
                        if rssVM.isValidatingFeed {
                            ProgressView()
                                .controlSize(.small)
                            Text(loc(.rssValidating))
                        } else {
                            Image(systemName: "plus.circle.fill")
                            Text(loc(.rssAddFeed))
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.roundedRectangle(radius: 12))
                .disabled(
                    newFeedURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || rssVM.isValidatingFeed
                )

                if let error = rssVM.errorMessage {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(AppColor.error)
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        } header: {
            Text(loc(.rssAddFeed))
        } footer: {
            Text(loc(.rssAddFeedFooter))
        }
    }

    // MARK: - Your Feeds Section

    @ViewBuilder
    private var yourFeedsSection: some View {
        if !feeds.isEmpty {
            Section {
                ForEach(feeds) { feed in
                    feedRow(feed)
                }
                .onDelete { offsets in
                    for index in offsets {
                        rssVM.removeFeed(feeds[index], modelContext: modelContext)
                    }
                }
            } header: {
                Text(loc(.rssYourFeeds))
            }
        }
    }

    private func feedRow(_ feed: RSSFeed) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "dot.radiowaves.up.and.down")
                .foregroundStyle(feed.isEnabled ? AppColor.accent : .secondary)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(feed.title)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)

                Text(feed.domain)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Toggle("", isOn: Binding(
                get: { feed.isEnabled },
                set: { _ in rssVM.toggleFeed(feed) }
            ))
            .labelsHidden()
        }
        .padding(.vertical, 2)
    }

    // MARK: - Actions

    private func addFeed() {
        let url = newFeedURL
        Task {
            await rssVM.addFeed(urlString: url, modelContext: modelContext)
            if rssVM.errorMessage == nil {
                newFeedURL = ""
            }
        }
    }
}
