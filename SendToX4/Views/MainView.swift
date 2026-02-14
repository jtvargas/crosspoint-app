import SwiftUI
import SwiftData

/// Root view with tab navigation.
struct MainView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \DeviceSettings.targetFolder) private var allSettings: [DeviceSettings]

    @State private var deviceVM = DeviceViewModel()
    @State private var convertVM = ConvertViewModel()
    @State private var historyVM = HistoryViewModel()

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
        TabView {
            Tab("Convert", systemImage: "doc.text.magnifyingglass") {
                ConvertView(
                    convertVM: convertVM,
                    deviceVM: deviceVM,
                    settings: settings
                )
            }

            Tab("History", systemImage: "clock.arrow.circlepath") {
                HistoryView(
                    historyVM: historyVM,
                    convertVM: convertVM,
                    deviceVM: deviceVM,
                    settings: settings
                )
            }

            if settings.showWallpaperX {
                Tab("WallpaperX", systemImage: "photo.artframe") {
                    WallpaperXView()
                }
            }

            if settings.showFileManager {
                Tab("Files", systemImage: "folder") {
                    FileManagerView()
                }
            }
        }
        .task {
            await deviceVM.search(settings: settings)
        }
    }
}
