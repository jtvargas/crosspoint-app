import SwiftUI

/// Placeholder view for the experimental File Manager feature.
struct FileManagerView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView {
                Label("File Manager", systemImage: "folder")
            } description: {
                Text("Coming soon — browse and manage files on your X4.")
            }
            .navigationTitle("File Manager")
        }
    }
}
