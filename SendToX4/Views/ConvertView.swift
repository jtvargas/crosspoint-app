import SwiftUI
import SwiftData
import StoreKit

/// Main conversion view — URL input, device status, and send button.
struct ConvertView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.requestReview) private var requestReview
    @Bindable var convertVM: ConvertViewModel
    var deviceVM: DeviceViewModel
    var queueVM: QueueViewModel
    @Bindable var rssVM: RSSFeedViewModel
    var settings: DeviceSettings
    @Binding var selectedTab: AppTab

    @Query(
        filter: #Predicate<Article> { $0.statusRaw == "sent" || $0.statusRaw == "savedLocally" },
        sort: \Article.createdAt,
        order: .reverse
    ) private var completedArticles: [Article]

    @Query(sort: \QueueItem.queuedAt) private var queueItems: [QueueItem]

    @State private var showShareSheet = false
    @State private var showLargeQueueWarning = false
    @State private var shareEPUBData: Data?
    @State private var shareFilename: String?
    @FocusState private var isURLFieldFocused: Bool

    private var recentArticles: [Article] {
        Array(completedArticles.prefix(3))
    }

    /// Formatted total size of all queued items (e.g. "1.2 MB").
    private var queueTotalSizeFormatted: String {
        let total = queueItems.reduce(Int64(0)) { $0 + $1.fileSize }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: total)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // URL Input Card
                    urlInputCard

                    // Action Buttons
                    actionButtons

                    // RSS Feeds Card
                    rssFeedCard

                    // Status / Error Display
                    statusDisplay

                    // Send Queue
                    queueSection

                    // Recent Conversions
                    recentConversionsSection

                    Spacer(minLength: 40)
                }
                .padding(.horizontal)
                .padding(.top, 8)
            }
            .navigationTitle(loc(.tabConvert))
            .settingsToolbar(deviceVM: deviceVM, settings: settings)
            .sheet(isPresented: $rssVM.showFeedSheet) {
                RSSFeedSheet(
                    rssVM: rssVM,
                    deviceVM: deviceVM,
                    queueVM: queueVM,
                    settings: settings
                )
            }
            .sheet(isPresented: $showShareSheet) {
                if let shareEPUBData, let shareFilename {
                    let tempURL = FileManager.default.temporaryDirectory
                        .appendingPathComponent(shareFilename)
                    ShareSheetView(items: [tempURL], epubData: shareEPUBData, filename: shareFilename)
                } else if let data = convertVM.lastEPUBData,
                          let filename = convertVM.lastFilename {
                    let tempURL = FileManager.default.temporaryDirectory
                        .appendingPathComponent(filename)
                    ShareSheetView(items: [tempURL], epubData: data, filename: filename)
                }
            }
            .onChange(of: convertVM.shouldRequestReview) { _, shouldPrompt in
                if shouldPrompt {
                    convertVM.shouldRequestReview = false
                    ReviewPromptManager.recordPromptShown()
                    requestReview()
                }
            }

        }
    }

    // MARK: - URL Input Card

    private var urlInputCard: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "link")
                    .foregroundStyle(.secondary)

                TextField(loc(.enterWebpageURL), text: $convertVM.urlString)
                    #if os(iOS)
                    .textContentType(.URL)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .submitLabel(.go)
                    #endif
                    .autocorrectionDisabled()
                    .focused($isURLFieldFocused)
                    .onSubmit {
                        if !convertVM.isProcessing {
                            Task {
                                await convertVM.convertAndSend(
                                    modelContext: modelContext,
                                    deviceVM: deviceVM,
                                    queueVM: queueVM,
                                    settings: settings
                                )
                            }
                        }
                    }

                if !convertVM.urlString.isEmpty {
                    Button {
                        convertVM.urlString = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                }

                PasteButton(payloadType: String.self) { strings in
                    if let url = strings.first {
                        convertVM.urlString = url
                    }
                }
                .labelStyle(.iconOnly)
                .buttonBorderShape(.capsule)
            }
            .padding()
            .glassEffect(.regular, in: .rect(cornerRadius: 16))
        }
    }

    // MARK: - Action Button

    /// Whether the button is in a brief post-success state (Sent / Queued).
    private var isSuccessPhase: Bool {
        !convertVM.isProcessing
        && (convertVM.currentPhase == .sent || convertVM.currentPhase == .savedLocally)
    }

    private var actionButtons: some View {
        Button {
            if !convertVM.isProcessing && !isSuccessPhase {
                isURLFieldFocused = false
                Task {
                    await convertVM.convertAndSend(
                        modelContext: modelContext,
                        deviceVM: deviceVM,
                        queueVM: queueVM,
                        settings: settings
                    )
                }
            }
        } label: {
            HStack {
                if convertVM.isProcessing {
                    if convertVM.currentPhase == .sending && deviceVM.uploadProgress > 0 {
                        // Determinate progress during upload
                        ProgressView(value: deviceVM.uploadProgress)
                            .progressViewStyle(.circular)
                            .tint(.white)
                        Text(loc(.sendingPercent, Int(deviceVM.uploadProgress * 100)))
                    } else {
                        ProgressView()
                            .tint(.white)
                        Text(convertVM.phaseLabel)
                    }
                } else if isSuccessPhase {
                    // Brief success confirmation (visible for ~1.5s before auto-reset)
                    Image(systemName: "checkmark.circle.fill")
                    Text(convertVM.phaseLabel)
                } else {
                    Image(systemName: deviceVM.isConnected
                          ? "paperplane.fill" : "doc.text")
                    Text(deviceVM.isConnected
                         ? loc(.convertAndSend) : loc(.convertToEPUB))
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .animation(.easeInOut(duration: 0.2), value: convertVM.currentPhase)
        }
        .buttonStyle(.borderedProminent)
        .tint(isSuccessPhase ? AppColor.success : nil)
        .buttonBorderShape(.roundedRectangle(radius: 16))
        .disabled(
            convertVM.urlString
                .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || convertVM.isProcessing
            || isSuccessPhase
        )
    }

    // MARK: - RSS Feed Card

    private var rssFeedCard: some View {
        Button {
            rssVM.showFeedSheet = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "dot.radiowaves.up.and.down")
                    .font(.title3)
                    .foregroundStyle(AppColor.accent)

                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(loc(.rssFeeds))
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.primary)

                        Spacer()

                        if rssVM.newArticleCount > 0 {
                            Text("\(rssVM.newArticleCount) \(loc(.rssNew))")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(.gray, in: Capsule())
                        }

                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }

                    if rssVM.isRefreshing {
                        HStack(spacing: 4) {
                            ProgressView()
                                .controlSize(.mini)
                            Text(loc(.rssRefreshing))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        let feeds = rssVM.fetchFeeds(modelContext: modelContext)
                        if feeds.isEmpty {
                            Text(loc(.rssTapToSetup))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Text(feeds.map(\.title).joined(separator: " \u{00B7} "))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .glassEffect(.regular, in: .rect(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Status Display

    @ViewBuilder
    private var statusDisplay: some View {
        if let error = convertVM.lastError {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(AppColor.error)
                Text(error)
                    .foregroundStyle(.secondary)
                    .font(.footnote)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(.regular, in: .rect(cornerRadius: 12))
        } else if !convertVM.statusMessage.isEmpty {
            HStack {
                Image(systemName: convertVM.currentPhase == .sent
                      ? "checkmark.circle.fill" : "info.circle.fill")
                    .foregroundStyle(convertVM.currentPhase == .sent
                                    ? AppColor.success : AppColor.accent)
                Text(convertVM.statusMessage)
                    .foregroundStyle(.secondary)
                    .font(.footnote)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(.regular, in: .rect(cornerRadius: 12))
        }
    }

    // MARK: - Recent Conversions

    @ViewBuilder
    private var recentConversionsSection: some View {
        if !recentArticles.isEmpty {
            VStack(spacing: 0) {
                // Section header
                HStack {
                    Text(loc(.recent))
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)

                    Spacer()

                    Button {
                        selectedTab = .history
                    } label: {
                        HStack(spacing: 2) {
                            Text(loc(.seeAll))
                            Image(systemName: "chevron.right")
                        }
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 4)
                .padding(.bottom, 8)

                // Rows inside a glass card
                VStack(spacing: 0) {
                    ForEach(Array(recentArticles.enumerated()), id: \.element.id) { index, article in
                        recentRow(article)

                        if index < recentArticles.count - 1 {
                            Divider()
                                .padding(.leading, 32)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .glassEffect(.regular, in: .rect(cornerRadius: 16))
            }
            .transition(.opacity.combined(with: .move(edge: .bottom)))
        }
    }

    private func recentRow(_ article: Article) -> some View {
        HStack(spacing: 10) {
            recentStatusIcon(for: article.status)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(article.title.isEmpty ? loc(.untitled) : article.title)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)

                HStack(spacing: 4) {
                    Text(article.sourceDomain)
                    Text("\u{00B7}")
                    Text(article.createdAt, format: .relative(presentation: .named))
                }
                .font(.caption2)
                .foregroundStyle(.tertiary)
            }

            Spacer(minLength: 0)

            recentMenu(for: article)
        }
        .padding(.vertical, 8)
    }

    private func recentMenu(for article: Article) -> some View {
        Menu {
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
                    Label(loc(.resendToX4), systemImage: "paperplane")
                }
            }

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
                Label(loc(.reconvertAndShare), systemImage: "square.and.arrow.up")
            }

            Button {
                ClipboardHelper.copy(article.url)
            } label: {
                Label(loc(.copyURL), systemImage: "doc.on.doc")
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private func recentStatusIcon(for status: ConversionStatus) -> some View {
        Group {
            switch status {
            case .sent:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(AppColor.success)
            case .savedLocally:
                Image(systemName: "arrow.down.circle.fill")
                    .foregroundStyle(AppColor.accent)
            default:
                Image(systemName: "circle.fill")
                    .foregroundStyle(.tertiary)
            }
        }
        .font(.subheadline)
    }

    // MARK: - Queue Section

    private var queueSection: some View {
        VStack(spacing: 0) {
            // Section header
            HStack {
                HStack(spacing: 4) {
                    Text(loc(.sendQueue))
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)

                    if !queueItems.isEmpty {
                        Text("·")
                            .font(.footnote)
                            .foregroundStyle(.quaternary)
                        Text(loc(.queueTotalSize, queueTotalSizeFormatted))
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.tertiary)
                    }
                }

                Spacer()

                if !queueItems.isEmpty {
                    if queueVM.isSending, let progress = queueVM.sendProgress {
                        HStack(spacing: 4) {
                            ProgressView()
                                .controlSize(.mini)
                            Text("\(progress.current)/\(progress.total)")
                                .font(.caption2.weight(.medium).monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    } else if deviceVM.isConnected {
                        Button {
                            if queueItems.count > QueueViewModel.largeQueueThreshold {
                                showLargeQueueWarning = true
                            } else {
                                Task {
                                    await queueVM.sendAll(
                                        deviceVM: deviceVM,
                                        settings: settings,
                                        modelContext: modelContext
                                    )
                                }
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "paperplane.fill")
                                Text(loc(.sendAll))
                            }
                            .font(.caption.weight(.medium))
                        }
                        .disabled(queueVM.isSending || queueVM.isSendingSingle)
                    }
                }
            }
            .padding(.horizontal, 4)
            .padding(.bottom, 8)

            // Content: populated or empty
            if queueItems.isEmpty {
                queueEmptyState
            } else {
                queueList
            }
        }
        .alert(loc(.largeQueueWarningTitle), isPresented: $showLargeQueueWarning) {
            Button(loc(.sendAnyway)) {
                Task {
                    await queueVM.sendAll(
                        deviceVM: deviceVM,
                        settings: settings,
                        modelContext: modelContext
                    )
                }
            }
            Button(loc(.cancel), role: .cancel) {}
        } message: {
            Text(loc(.largeQueueWarningMessage,
                      queueItems.count,
                      QueueViewModel.formatTransferTime(for: queueItems))
                 + loc(.estimateImprovesNotice))
        }
    }

    private var queueEmptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "tray")
                .font(.title2)
                .foregroundStyle(.tertiary)

            Text(loc(.noItemsQueued))
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)

            Text(loc(.queueEmptyDescription))
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
    }

    private var queueList: some View {
        VStack(spacing: 0) {
            ForEach(Array(queueItems.enumerated()), id: \.element.id) { index, item in
                queueRow(item)

                if index < queueItems.count - 1 {
                    Divider()
                        .padding(.leading, 32)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
    }

    private func queueRow(_ item: QueueItem) -> some View {
        let isPending = queueVM.pendingSendIDs.contains(item.id)

        return HStack(spacing: 10) {
            // Leading icon: spinner when this item is pending/sending, doc icon otherwise
            if isPending {
                ProgressView()
                    .controlSize(.mini)
                    .frame(width: 20)
            } else {
                Image(systemName: "doc.text.fill")
                    .foregroundStyle(AppColor.accent)
                    .frame(width: 20)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)

                HStack(spacing: 4) {
                    Text(item.sourceDomain)
                    Text("\u{00B7}")
                    Text(item.formattedSize)
                }
                .font(.caption2)
                .foregroundStyle(.tertiary)
            }

            Spacer(minLength: 0)

            // Send button (visible when connected and not in batch send)
            if deviceVM.isConnected && !queueVM.isSending && !isPending {
                Button {
                    queueVM.enqueueSend(
                        item,
                        deviceVM: deviceVM,
                        settings: settings,
                        modelContext: modelContext
                    )
                } label: {
                    Image(systemName: "paperplane.fill")
                        .font(.subheadline)
                        .foregroundStyle(AppColor.accent)
                }
                .buttonStyle(.plain)
            }

            // Remove button (hidden when item is pending send)
            if !isPending {
                Button(role: .destructive) {
                    withAnimation {
                        queueVM.remove(item, modelContext: modelContext)
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 8)
    }
}

// MARK: - Share Sheet

#if canImport(UIKit)
import UIKit

/// UIActivityViewController wrapper for sharing EPUB files on iOS/iPadOS.
struct ShareSheetView: UIViewControllerRepresentable {
    let items: [Any]
    let epubData: Data
    let filename: String

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(filename)
        try? epubData.write(to: tempURL)

        return UIActivityViewController(
            activityItems: [tempURL],
            applicationActivities: nil
        )
    }

    func updateUIViewController(
        _ uiViewController: UIActivityViewController,
        context: Context
    ) {}
}

#elseif canImport(AppKit)
import AppKit

/// NSSharingServicePicker wrapper for sharing EPUB files on macOS.
struct ShareSheetView: NSViewRepresentable {
    let items: [Any]
    let epubData: Data
    let filename: String

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        // Trigger the share picker after the view appears
        DispatchQueue.main.async {
            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(filename)
            try? epubData.write(to: tempURL)

            let picker = NSSharingServicePicker(items: [tempURL])
            picker.show(relativeTo: view.bounds, of: view, preferredEdge: .minY)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
#endif
