import SwiftUI
import SwiftData

/// Identifies which tab is currently selected.
enum AppTab: Hashable {
    case convert
    case wallpaperX
    case files
    case history
}

/// Root view with tab navigation.
struct MainView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \DeviceSettings.convertFolder) private var allSettings: [DeviceSettings]
    @Query(sort: \Article.createdAt, order: .reverse) private var articles: [Article]
    @Query(sort: \ActivityEvent.timestamp, order: .reverse) private var activities: [ActivityEvent]

    @State private var deviceVM = DeviceViewModel()
    @State private var convertVM = ConvertViewModel()
    @State private var queueVM = QueueViewModel()
    @State private var historyVM = HistoryViewModel()
    @State private var wallpaperVM = WallpaperViewModel()
    @State private var selectedTab: AppTab = .convert
    @State private var showAdvancedWallpaperSettings = false
    @State private var showQueuePrompt = false

    @Query(sort: \QueueItem.queuedAt) private var queueItems: [QueueItem]

    /// Ensure a DeviceSettings singleton exists.
    private var settings: DeviceSettings {
        if let existing = allSettings.first {
            return existing
        }
        let new = DeviceSettings()
        modelContext.insert(new)
        return new
    }

    var body: some View {
        #if os(macOS)
        VStack(spacing: 0) {
            tabContent
            Divider()
            MacDeviceStatusBar(
                deviceVM: deviceVM,
                settings: settings
            )
        }
        .task {
            await deviceVM.search(settings: settings)
        }
        .onChange(of: deviceVM.isConnected) { _, isConnected in
            if isConnected && !queueItems.isEmpty {
                showQueuePrompt = true
            }
        }
        .alert(
            loc(.sendQueuedFilesTitle),
            isPresented: $showQueuePrompt
        ) {
            Button(loc(.sendAllCount, queueItems.count)) {
                Task {
                    await queueVM.sendAll(
                        deviceVM: deviceVM,
                        settings: settings,
                        modelContext: modelContext
                    )
                }
            }
            Button(loc(.later), role: .cancel) {}
        } message: {
            Text(loc(.sendQueuedFilesMessage, queueItems.count))
        }
        #else
        tabContent
            .tabViewBottomAccessory {
                if selectedTab == .wallpaperX {
                    WallpaperQuickControls(
                        wallpaperVM: wallpaperVM,
                        deviceVM: deviceVM,
                        showAdvancedSettings: $showAdvancedWallpaperSettings
                    )
                } else {
                    DeviceConnectionAccessory(
                        deviceVM: deviceVM,
                        convertVM: convertVM,
                        settings: settings,
                        queueCount: queueItems.count
                    )
                }
            }
            .sheet(isPresented: $showAdvancedWallpaperSettings) {
                WallpaperAdvancedSheet(wallpaperVM: wallpaperVM)
            }
            .task {
                await deviceVM.search(settings: settings)
            }
            .onChange(of: deviceVM.isConnected) { _, isConnected in
                if isConnected && !queueItems.isEmpty {
                    showQueuePrompt = true
                }
            }
            .alert(
                loc(.sendQueuedFilesTitle),
                isPresented: $showQueuePrompt
            ) {
                Button(loc(.sendAllCount, queueItems.count)) {
                    Task {
                        await queueVM.sendAll(
                            deviceVM: deviceVM,
                            settings: settings,
                            modelContext: modelContext
                        )
                    }
                }
                Button(loc(.later), role: .cancel) {}
            } message: {
                Text(loc(.sendQueuedFilesMessage, queueItems.count))
            }
        #endif
    }

    private var tabContent: some View {
        TabView(selection: $selectedTab) {
            Tab(loc(.tabConvert), systemImage: "doc.text.magnifyingglass", value: .convert) {
                ConvertView(
                    convertVM: convertVM,
                    deviceVM: deviceVM,
                    queueVM: queueVM,
                    settings: settings,
                    selectedTab: $selectedTab
                )
            }

            Tab(loc(.tabWallpaperX), systemImage: "photo.artframe", value: .wallpaperX) {
                WallpaperXView(
                    wallpaperVM: wallpaperVM,
                    deviceVM: deviceVM,
                    settings: settings
                )
            }

            Tab(loc(.tabFiles), systemImage: "folder", value: .files) {
                FileManagerView(
                    deviceVM: deviceVM,
                    settings: settings
                )
            }

            Tab(loc(.tabHistory), systemImage: "clock.arrow.circlepath", value: .history) {
                HistoryView(
                    historyVM: historyVM,
                    convertVM: convertVM,
                    deviceVM: deviceVM,
                    settings: settings
                )
            }
            .badge(historyVM.unseenCount(articles: articles, activities: activities))
        }
        .onChange(of: selectedTab) { _, newTab in
            if newTab == .history {
                historyVM.markAsSeen()
            }
        }
    }
}
