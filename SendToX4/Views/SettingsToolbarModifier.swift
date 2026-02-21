import SwiftUI

/// Reusable modifier that adds a Settings gear button to the top-leading toolbar
/// and presents the SettingsSheet when tapped. Apply inside any NavigationStack.
struct SettingsToolbarModifier: ViewModifier {
    var deviceVM: DeviceViewModel
    var settings: DeviceSettings
    var toast: ToastManager?

    @State private var showSettings = false
    @State private var showAbout = false

    func body(content: Content) -> some View {
        content
            .toolbar {
                ToolbarItem(placement: .navigation) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showAbout = true
                    } label: {
                        Image(systemName: "info.circle")
                    }
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsSheet(deviceVM: deviceVM, settings: settings, toast: toast)
            }
            .sheet(isPresented: $showAbout) {
                AboutAppView()
            }
    }
}

extension View {
    /// Adds a top-leading Settings gear button that opens the SettingsSheet.
    func settingsToolbar(deviceVM: DeviceViewModel, settings: DeviceSettings, toast: ToastManager? = nil) -> some View {
        modifier(SettingsToolbarModifier(deviceVM: deviceVM, settings: settings, toast: toast))
    }
}
