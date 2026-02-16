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
    @State private var showClearHistoryConfirm = false
    @State private var showClearCacheConfirm = false
    @State private var showClearQueueConfirm = false

    var body: some View {
        NavigationStack {
            Form {
                // MARK: - Device Section

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

                // MARK: - Feature Folders Section

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

                // MARK: - Connection Test

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

                // MARK: - Storage Section

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

                // MARK: - About Section

                Section {
                    LabeledContent("Version", value: "1.0")
                    LabeledContent("EPUB Format", value: "EPUB 2.0")
                } header: {
                    Text("About")
                }
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
            .confirmationDialog(
                "Clear History Data?",
                isPresented: $showClearHistoryConfirm,
                titleVisibility: .visible
            ) {
                Button("Clear History", role: .destructive) {
                    clearHistoryData()
                }
            } message: {
                Text("This will permanently delete all conversion history and file activity logs.")
            }
            .confirmationDialog(
                "Clear Web Cache?",
                isPresented: $showClearCacheConfirm,
                titleVisibility: .visible
            ) {
                Button("Clear Cache", role: .destructive) {
                    clearWebCache()
                }
            } message: {
                Text("Cached web pages will be removed. Future conversions may take slightly longer.")
            }
            .confirmationDialog(
                "Clear EPUB Queue?",
                isPresented: $showClearQueueConfirm,
                titleVisibility: .visible
            ) {
                Button("Clear Queue", role: .destructive) {
                    clearQueue()
                }
            } message: {
                Text("All \(queueItems.count) queued EPUB\(queueItems.count == 1 ? "" : "s") will be permanently deleted.")
            }
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
