import SwiftUI

/// Placeholder view for the experimental WallpaperX feature.
struct WallpaperXView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView {
                Label("WallpaperX", systemImage: "photo.artframe")
            } description: {
                Text("Coming soon — custom wallpapers for your X4.")
            }
            .navigationTitle("WallpaperX")
        }
    }
}
