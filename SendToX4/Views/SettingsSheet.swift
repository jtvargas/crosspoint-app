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
                deviceSection
                featureFoldersSection
                connectionTestSection
                feedbackSection
                siriShortcutSection
                storageSection
                aboutSection
            }
            .navigationTitle("Settings")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task {
                refreshStorageSizes()
            }
            .alert("Clear History Data?", isPresented: $showClearHistoryConfirm) {
                Button("Clear History", role: .destructive) {
                    clearHistoryData()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will permanently delete all conversion history and file activity logs.")
            }
            .alert("Clear Web Cache?", isPresented: $showClearCacheConfirm) {
                Button("Clear Cache", role: .destructive) {
                    clearWebCache()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Cached web pages will be removed. Future conversions may take slightly longer.")
            }
            .alert("Clear EPUB Queue?", isPresented: $showClearQueueConfirm) {
                Button("Clear Queue", role: .destructive) {
                    clearQueue()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("All \(queueItems.count) queued EPUB\(queueItems.count == 1 ? "" : "s") will be permanently deleted.")
            }
        }
    }

    // MARK: - Device Section

    private var deviceSection: some View {
        Section {
            Picker("Firmware", selection: $settings.firmwareType) {
                ForEach(FirmwareType.allCases, id: \.self) { type in
                    Text(type.rawValue).tag(type)
                }
            }

            if settings.firmwareType == .custom {
                TextField("Device IP Address", text: $settings.customIP)
                    #if os(iOS)
                    .keyboardType(.decimalPad)
                    .textContentType(.none)
                    #endif
            }

            LabeledContent("Address", value: settings.resolvedHost)
                .foregroundStyle(.secondary)
        } header: {
            Text("Device")
        } footer: {
            Text("CrossPoint uses crosspoint.local (fallback: 192.168.4.1). Stock uses 192.168.3.3.")
        }
    }

    // MARK: - Feature Folders Section

    private var featureFoldersSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 4) {
                Text("Convert")
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
                Text("WallpaperX")
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
            Text("Feature Folders")
        } footer: {
            Text("Each feature uploads to its own folder on the device (e.g. /\(settings.convertFolder)/). Tap a field to change the destination.")
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
                        ? "Connected (\(deviceVM.firmwareLabel))"
                        : "Not reachable"
                    isTesting = false
                }
            } label: {
                HStack {
                    Text("Test Connection")
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
                Text("Convert web pages to EPUB directly from the Share menu using a Siri Shortcut and add it to the Queue")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 10) {
                    setupStep(1, "Open the **Shortcuts** app")
                    setupStep(2, "Tap **+** to create a new Shortcut")
                    setupStep(3, "Search for **\"CrossX\"** in the search bar")
                    setupStep(3, "Press **\"Convert to EPUB & Add to Queue\"**")
                    setupStep(4, "Tap the **info icon** (i) at the bottom")
                    setupStep(5, "Enable **\"Show in Share Sheet\"** and close it")
                    setupStep(6, "Press **\"Web Page URL\"** input")
                    setupStep(7, "Press **\"Select Variable\"**")
                    setupStep(8, "Press **\"Shortcut Input\"**")
                    setupStep(9, "Done")
                }

                #if os(iOS)
                Button {
                    if let url = URL(string: "shortcuts://") {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    HStack {
                        Spacer()
                        Label("Open Shortcuts App", systemImage: "arrow.up.forward.app")
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
            Text("Siri Shortcut")
        } footer: {
            Text("The shortcut converts pages in the background and queues them for sending when your X4 connects.")
        }
    }

    // MARK: - Storage Section

    private var storageSection: some View {
        Section {
            LabeledContent("Database") {
                Text(StorageCalculator.formatted(databaseSize))
                    .foregroundStyle(.secondary)
            }
            LabeledContent("Web Cache") {
                Text(StorageCalculator.formatted(webCacheSize))
                    .foregroundStyle(.secondary)
            }
            LabeledContent("Temp Files") {
                Text(StorageCalculator.formatted(tempSize))
                    .foregroundStyle(.secondary)
            }
            LabeledContent("Queue (\(queueItems.count) EPUB\(queueItems.count == 1 ? "" : "s"))") {
                Text(StorageCalculator.formatted(queueSize))
                    .foregroundStyle(.secondary)
            }

            Button("Clear History Data", role: .destructive) {
                showClearHistoryConfirm = true
            }

            Button("Clear Web Cache", role: .destructive) {
                showClearCacheConfirm = true
            }

            if !queueItems.isEmpty {
                Button("Clear Queue", role: .destructive) {
                    showClearQueueConfirm = true
                }
            }
        } header: {
            Text("Storage")
        } footer: {
            Text("Database includes conversion history and file activity logs. Web Cache stores fetched web pages for faster re-conversion.")
        }
    }

    // MARK: - Feedback & Support

    private var feedbackSection: some View {
        Section {
            Button {
                openURL(Self.githubCodeURL)
            } label: {
                Label("Source Code", systemImage: "chevron.left.forwardslash.chevron.right")
            }
            
            Button {
                openURL(Self.githubIssuesURL)
            } label: {
                Label("Feature Requests", systemImage: "lightbulb")
            }

            Button {
                openURL(Self.githubIssuesURL)
            } label: {
                Label("Report a Bug", systemImage: "ladybug")
            }
        } header: {
            Text("Feedback & Support")
        } footer: {
            Text("Opens GitHub Issues where you can suggest features or report bugs. Also you can inspect the Source Code")
        }
    }

    private static let githubIssuesURL = URL(string: "https://github.com/jtvargas/crosspoint-app/issues/new/choose")!
    private static let githubCodeURL = URL(string: "https://github.com/jtvargas/crosspoint-app")!

    // MARK: - About Section

    private var aboutSection: some View {
        Section {
            LabeledContent("Version", value: "1.0")
            LabeledContent("EPUB Format", value: "EPUB 2.0")

            Button {
                hasSeenOnboarding = false
                dismiss()
            } label: {
                HStack {
                    Label("Show Onboarding", systemImage: "hand.wave")
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        } header: {
            Text("About")
        }
    }

    // MARK: - Setup Guide Helper

    private func setupStep(_ number: Int, _ text: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(number)")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 20, height: 20)
                .background(AppColor.accent, in: .circle)

            Text(text)
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
