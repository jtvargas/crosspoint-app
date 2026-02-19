import AlertToast
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
    @State private var rssVM = RSSFeedViewModel()
    @State private var toast = ToastManager()
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
                queueVM: queueVM,
                rssVM: rssVM,
                settings: settings
            )
        }
        .task {
            await deviceVM.search(settings: settings)
            await rssVM.refreshAllFeeds(modelContext: modelContext)
        }
        .onChange(of: deviceVM.isConnected) { _, isConnected in
            if isConnected && !queueItems.isEmpty && !deviceVM.isBatchDeleting {
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
                        modelContext: modelContext,
                        toast: toast
                    )
                }
            }
            Button(loc(.later), role: .cancel) {}
        } message: {
            if queueItems.count > QueueViewModel.largeQueueThreshold {
                Text(loc(.largeQueueWarningMessage,
                          queueItems.count,
                          QueueViewModel.formatTransferTime(for: queueItems))
                     + loc(.estimateImprovesNotice))
            } else {
                Text(loc(.sendQueuedFilesMessage, queueItems.count))
            }
        }
        .toast(isPresenting: $toast.showHUD, duration: 2.5, tapToDismiss: true) {
            toast.hudToast
        }
        .toast(isPresenting: $toast.showCenter, duration: 1.5, tapToDismiss: true) {
            toast.centerToast
        }
        #else
        tabContent
            .tabViewBottomAccessory {
                if selectedTab == .wallpaperX {
                    WallpaperQuickControls(
                        wallpaperVM: wallpaperVM,
                        deviceVM: deviceVM,
                        queueVM: queueVM,
                        rssVM: rssVM,
                        showAdvancedSettings: $showAdvancedWallpaperSettings
                    )
                } else {
                    DeviceConnectionAccessory(
                        deviceVM: deviceVM,
                        convertVM: convertVM,
                        queueVM: queueVM,
                        rssVM: rssVM,
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
                await rssVM.refreshAllFeeds(modelContext: modelContext)
            }
            .onChange(of: deviceVM.isConnected) { _, isConnected in
                if isConnected && !queueItems.isEmpty && !deviceVM.isBatchDeleting {
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
                            modelContext: modelContext,
                            toast: toast
                        )
                    }
                }
                Button(loc(.later), role: .cancel) {}
            } message: {
                if queueItems.count > QueueViewModel.largeQueueThreshold {
                    Text(loc(.largeQueueWarningMessage,
                              queueItems.count,
                              QueueViewModel.formatTransferTime(for: queueItems))
                         + loc(.estimateImprovesNotice))
                } else {
                    Text(loc(.sendQueuedFilesMessage, queueItems.count))
                }
            }
            .toast(isPresenting: $toast.showHUD, duration: 2.5, tapToDismiss: true) {
                toast.hudToast
            }
            .toast(isPresenting: $toast.showCenter, duration: 1.5, tapToDismiss: true) {
                toast.centerToast
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
                    rssVM: rssVM,
                    settings: settings,
                    toast: toast,
                    selectedTab: $selectedTab
                )
            }

            Tab(loc(.tabWallpaperX), systemImage: "photo.artframe", value: .wallpaperX) {
                WallpaperXView(
                    wallpaperVM: wallpaperVM,
                    deviceVM: deviceVM,
                    settings: settings,
                    toast: toast
                )
            }

            Tab(loc(.tabFiles), systemImage: "folder", value: .files) {
                FileManagerView(
                    deviceVM: deviceVM,
                    settings: settings,
                    toast: toast
                )
            }

            Tab(loc(.tabHistory), systemImage: "clock.arrow.circlepath", value: .history) {
                HistoryView(
                    historyVM: historyVM,
                    convertVM: convertVM,
                    deviceVM: deviceVM,
                    settings: settings,
                    toast: toast
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
