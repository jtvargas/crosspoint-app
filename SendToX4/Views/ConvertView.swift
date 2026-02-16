import SwiftUI
import SwiftData
import StoreKit

/// Main conversion view — URL input, device status, and send button.
struct ConvertView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.requestReview) private var requestReview
    @Bindable var convertVM: ConvertViewModel
    var deviceVM: DeviceViewModel
    var settings: DeviceSettings
    @Binding var selectedTab: AppTab

    @Query(
        filter: #Predicate<Article> { $0.statusRaw == "sent" || $0.statusRaw == "savedLocally" },
        sort: \Article.createdAt,
        order: .reverse
    ) private var completedArticles: [Article]

    @State private var showShareSheet = false
    @State private var selectedArticle: Article?
    @State private var shareEPUBData: Data?
    @State private var shareFilename: String?
    @FocusState private var isURLFieldFocused: Bool

    private var recentArticles: [Article] {
        Array(completedArticles.prefix(5))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // URL Input Card
                    urlInputCard

                    // Action Buttons
                    actionButtons

                    // Status / Error Display
                    statusDisplay

                    // Recent Conversions
                    recentConversionsSection

                    Spacer(minLength: 40)
                }
                .padding(.horizontal)
                .padding(.top, 8)
            }
            .navigationTitle("Convert")
            .settingsToolbar(deviceVM: deviceVM, settings: settings)
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
            // MARK: - Article Action Dialog
            .confirmationDialog(
                selectedArticle?.title ?? "Article",
                isPresented: Binding(
                    get: { selectedArticle != nil },
                    set: { if !$0 { selectedArticle = nil } }
                ),
                titleVisibility: .visible,
                presenting: selectedArticle
            ) { article in
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

                Button("Copy URL") {
                    ClipboardHelper.copy(article.url)
                }

                Button("Cancel", role: .cancel) {}
            } message: { article in
                Text(article.sourceDomain)
            }
        }
    }

    // MARK: - URL Input Card

    private var urlInputCard: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "link")
                    .foregroundStyle(.secondary)

                TextField("Enter webpage URL", text: $convertVM.urlString)
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

    // MARK: - Action Buttons

    private var actionButtons: some View {
        VStack(spacing: 12) {
            // Primary: Convert & Send
            Button {
                isURLFieldFocused = false
                Task {
                    await convertVM.convertAndSend(
                        modelContext: modelContext,
                        deviceVM: deviceVM,
                        settings: settings
                    )
                }
            } label: {
                HStack {
                    if convertVM.isProcessing {
                        if convertVM.currentPhase == .sending && deviceVM.uploadProgress > 0 {
                            // Determinate progress during upload
                            ProgressView(value: deviceVM.uploadProgress)
                                .progressViewStyle(.circular)
                                .tint(.white)
                            Text("Sending \(Int(deviceVM.uploadProgress * 100))%")
                        } else {
                            ProgressView()
                                .tint(.white)
                            Text(convertVM.phaseLabel)
                        }
                    } else {
                        Image(systemName: deviceVM.isConnected
                              ? "paperplane.fill" : "doc.text")
                        Text(deviceVM.isConnected
                             ? "Convert & Send" : "Convert to EPUB")
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.roundedRectangle(radius: 16))
            .disabled(
                convertVM.urlString
                    .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || convertVM.isProcessing
            )

            // Secondary: Save to Files
            if convertVM.lastEPUBData != nil {
                Button {
                    showShareSheet = true
                } label: {
                    HStack {
                        Image(systemName: "square.and.arrow.up")
                        Text("Save to Files")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.roundedRectangle(radius: 16))
            }
        }
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
                    Text("Recent")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)

                    Spacer()

                    Button {
                        selectedTab = .history
                    } label: {
                        HStack(spacing: 2) {
                            Text("See All")
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
                            .contentShape(Rectangle())
                            .onTapGesture {
                                selectedArticle = article
                            }

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
                Text(article.title.isEmpty ? "Untitled" : article.title)
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

            Image(systemName: "ellipsis")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 8)
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
