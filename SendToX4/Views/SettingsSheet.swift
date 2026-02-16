import SwiftUI
import SwiftData

/// Device configuration sheet with native iOS Settings style.
struct SettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    var deviceVM: DeviceViewModel
    @Bindable var settings: DeviceSettings

    @Query(sort: \QueueItem.queuedAt) private var queueItems: [QueueItem]

    @State private var isTesting = false
    @State private var testResult: String?

    // Storage
    @State private var databaseSize: Int64 = 0
    @State private var webCacheSize: Int64 = 0
    @State private var tempSize: Int64 = 0
    @State private var queueSize: Int64 = 0
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = true
    @State private var showClearHistoryConfirm = false
    @State private var showClearCacheConfirm = false
    @State private var showClearQueueConfirm = false
    @Environment(\.openURL) private var openURL

    var body: some View {
        NavigationStack {
            Form {
                languageSection
                deviceSection
                featureFoldersSection
                connectionTestSection
                feedbackSection
                siriShortcutSection
                storageSection
                debugLogsSection
                aboutSection
            }
            .navigationTitle(loc(.settings))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(loc(.done)) { dismiss() }
                }
            }
            .task {
                refreshStorageSizes()
            }
            .onChange(of: settings.appLanguage) { _, newLang in
                LocalizationManager.shared.currentLanguage = newLang
            }
            .alert(loc(.clearHistoryDataTitle), isPresented: $showClearHistoryConfirm) {
                Button(loc(.clearHistory), role: .destructive) {
                    clearHistoryData()
                }
                Button(loc(.cancel), role: .cancel) {}
            } message: {
                Text(loc(.clearHistoryDataMessage))
            }
            .alert(loc(.clearWebCacheTitle), isPresented: $showClearCacheConfirm) {
                Button(loc(.clearCache), role: .destructive) {
                    clearWebCache()
                }
                Button(loc(.cancel), role: .cancel) {}
            } message: {
                Text(loc(.clearWebCacheMessage))
            }
            .alert(loc(.clearEPUBQueueTitle), isPresented: $showClearQueueConfirm) {
                Button(loc(.clearQueue), role: .destructive) {
                    clearQueue()
                }
                Button(loc(.cancel), role: .cancel) {}
            } message: {
                Text(loc(.clearEPUBQueueMessage, queueItems.count))
            }
        }
    }

    // MARK: - Language Section
    private var languageSection: some View {
        Section {
            Picker(loc(.language), selection: $settings.appLanguage) {
                ForEach(AppLanguage.allCases, id: \.self) { lang in
                    Text(lang.displayName).tag(lang)
                }
            }
        } header: {
            Text(loc(.language))
        }
    }

    // MARK: - Device Section

    private var deviceSection: some View {
        Section {
            Picker(loc(.firmware), selection: $settings.firmwareType) {
                ForEach(FirmwareType.allCases, id: \.self) { type in
                    Text(type.displayName).tag(type)
                }
            }

            if settings.firmwareType == .custom {
                TextField(loc(.deviceIPAddress), text: $settings.customIP)
                    #if os(iOS)
                    .keyboardType(.decimalPad)
                    .textContentType(.none)
                    #endif
            }

            LabeledContent(loc(.address), value: settings.resolvedHost)
                .foregroundStyle(.secondary)
        } header: {
            Text(loc(.device))
        } footer: {
            Text(loc(.firmwareIPDescription))
        }
    }

    // MARK: - Feature Folders Section

    private var featureFoldersSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 4) {
                Text(loc(.convertSectionLabel))
                    .font(.subheadline.weight(.medium))
                HStack {
                    Image(systemName: "folder")
                        .foregroundStyle(.secondary)
                    TextField("content", text: $settings.convertFolder)
                        .autocorrectionDisabled()
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        #endif
                }
            }
            .padding(.vertical, 2)

            VStack(alignment: .leading, spacing: 4) {
                Text(loc(.wallpaperXSectionLabel))
                    .font(.subheadline.weight(.medium))
                HStack {
                    Image(systemName: "folder")
                        .foregroundStyle(.secondary)
                    TextField("sleep", text: $settings.wallpaperFolder)
                        .autocorrectionDisabled()
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        #endif
                }
            }
            .padding(.vertical, 2)
        } header: {
            Text(loc(.featureFolders))
        } footer: {
            Text(loc(.featureFoldersDescription, settings.convertFolder))
        }
    }

    // MARK: - Connection Test

    private var connectionTestSection: some View {
        Section {
            Button {
                Task {
                    isTesting = true
                    testResult = nil
                    await deviceVM.refresh(settings: settings)
                    testResult = deviceVM.isConnected
                        ? loc(.connectedWithInfo, deviceVM.firmwareLabel)
                        : loc(.notReachable)
                    isTesting = false
                }
            } label: {
                HStack {
                    Text(loc(.testConnection))
                    Spacer()
                    if isTesting {
                        ProgressView()
                            .controlSize(.small)
                    } else if let result = testResult {
                        Text(result)
                            .foregroundStyle(
                                deviceVM.isConnected ? AppColor.success : AppColor.error
                            )
                            .font(.footnote)
                    }
                }
            }
            .disabled(isTesting)
        }
    }

    // MARK: - Siri Shortcut Setup

    private var siriShortcutSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                Text(loc(.siriShortcutDescription))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 10) {
                    setupStep(1, loc(.siriStep1))
                    setupStep(2, loc(.siriStep2))
                    setupStep(3, loc(.siriStep3))
                    setupStep(3, loc(.siriStep4))
                    setupStep(4, loc(.siriStep5))
                    setupStep(5, loc(.siriStep6))
                    setupStep(6, loc(.siriStep7))
                    setupStep(7, loc(.siriStep8))
                    setupStep(8, loc(.siriStep9))
                }

                #if os(iOS)
                Button {
                    if let url = URL(string: "shortcuts://") {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    HStack {
                        Spacer()
                        Label(loc(.openShortcutsApp), systemImage: "arrow.up.forward.app")
                            .font(.subheadline.weight(.medium))
                        Spacer()
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(AppColor.accent)
                .padding(.top, 4)
                #endif
            }
            .padding(.vertical, 4)
        } header: {
            Text(loc(.siriShortcut))
        } footer: {
            Text(loc(.siriShortcutFooter))
        }
    }

    // MARK: - Storage Section

    private var storageSection: some View {
        Section {
            LabeledContent(loc(.database)) {
                Text(StorageCalculator.formatted(databaseSize))
                    .foregroundStyle(.secondary)
            }
            LabeledContent(loc(.webCache)) {
                Text(StorageCalculator.formatted(webCacheSize))
                    .foregroundStyle(.secondary)
            }
            LabeledContent(loc(.tempFiles)) {
                Text(StorageCalculator.formatted(tempSize))
                    .foregroundStyle(.secondary)
            }
            LabeledContent(loc(.queueEPUBCount, queueItems.count)) {
                Text(StorageCalculator.formatted(queueSize))
                    .foregroundStyle(.secondary)
            }

            Button(loc(.clearHistoryData), role: .destructive) {
                showClearHistoryConfirm = true
            }

            Button(loc(.clearWebCache), role: .destructive) {
                showClearCacheConfirm = true
            }

            if !queueItems.isEmpty {
                Button(loc(.clearQueue), role: .destructive) {
                    showClearQueueConfirm = true
                }
            }
        } header: {
            Text(loc(.storage))
        } footer: {
            Text(loc(.storageDescription))
        }
    }

    // MARK: - Debug Logs Section

    private var debugLogsSection: some View {
        Section {
            NavigationLink {
                DebugLogView()
            } label: {
                HStack {
                    Label(loc(.debugLogs), systemImage: "doc.text")
                    Spacer()
                    Text(loc(.debugLogsEntryCount, DebugLogger.shared.entryCount))
                        .foregroundStyle(.secondary)
                        .font(.footnote)
                }
            }
        } footer: {
            Text(DebugLogger.shared.formattedLogSize)
        }
    }

    // MARK: - Feedback & Support

    private var feedbackSection: some View {
        Section {
            Button {
                openURL(Self.githubCodeURL)
            } label: {
                Label(loc(.sourceCode), systemImage: "chevron.left.forwardslash.chevron.right")
            }
            
            Button {
                openURL(Self.githubIssuesURL)
            } label: {
                Label(loc(.featureRequests), systemImage: "lightbulb")
            }

            Button {
                openURL(Self.githubIssuesURL)
            } label: {
                Label(loc(.reportABug), systemImage: "ladybug")
            }
        } header: {
            Text(loc(.feedbackAndSupport))
        } footer: {
            Text(loc(.feedbackDescription))
        }
    }

    private static let githubIssuesURL = URL(string: "https://github.com/jtvargas/crosspoint-app/issues/new/choose")!
    private static let githubCodeURL = URL(string: "https://github.com/jtvargas/crosspoint-app")!

    // MARK: - About Section

    private var aboutSection: some View {
        Section {
            LabeledContent(loc(.version), value: "1.0")
            LabeledContent(loc(.epubFormat), value: "EPUB 2.0")

            Button {
                hasSeenOnboarding = false
                dismiss()
            } label: {
                HStack {
                    Label(loc(.showOnboarding), systemImage: "hand.wave")
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        } header: {
            Text(loc(.about))
        }
    }

    // MARK: - Setup Guide Helper

    private func setupStep(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(number)")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 20, height: 20)
                .background(AppColor.accent, in: .circle)

            Text(LocalizedStringKey(text))
                .font(.subheadline)
        }
    }

    // MARK: - Storage Helpers

    private func refreshStorageSizes() {
        databaseSize = StorageCalculator.swiftDataStoreSize()
        webCacheSize = StorageCalculator.urlCacheSize()
        tempSize = StorageCalculator.tempDirectorySize()
        queueSize = StorageCalculator.queueDirectorySize()
    }

    private func clearHistoryData() {
        do {
            try modelContext.delete(model: Article.self)
            try modelContext.delete(model: ActivityEvent.self)
        } catch {
            // Silently handle — clearing is non-critical
        }
        refreshStorageSizes()
    }

    private func clearWebCache() {
        URLCache.shared.removeAllCachedResponses()
        refreshStorageSizes()
    }

    private func clearQueue() {
        // Delete all files in the queue directory
        let dirURL = QueueViewModel.queueDirectoryURL
        if let contents = try? FileManager.default.contentsOfDirectory(
            at: dirURL, includingPropertiesForKeys: nil
        ) {
            for fileURL in contents {
                try? FileManager.default.removeItem(at: fileURL)
            }
        }
        // Delete all QueueItem records
        try? modelContext.delete(model: QueueItem.self)
        refreshStorageSizes()
    }
}
