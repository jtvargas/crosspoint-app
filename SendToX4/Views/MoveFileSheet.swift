import SwiftUI

/// Sheet for selecting a destination folder to move a file into.
struct MoveFileSheet: View {
    @Environment(\.dismiss) private var dismiss

    let file: DeviceFile
    var fetchFolders: (String) async -> [DeviceFile]
    var onMove: (String) async -> Bool

    @State private var currentPath = "/"
    @State private var folders: [DeviceFile] = []
    @State private var isLoading = false
    @State private var isMoving = false

    /// Breadcrumb components for the current path.
    private var pathComponents: [(name: String, path: String)] {
        var components: [(name: String, path: String)] = [("/", "/")]
        guard currentPath != "/" else { return components }
        let parts = currentPath.split(separator: "/").map(String.init)
        var accumulated = ""
        for part in parts {
            accumulated += "/\(part)"
            components.append((part, accumulated))
        }
        return components
    }

    /// Parent directory of the file being moved.
    private var fileParent: String {
        let parent = (file.path as NSString).deletingLastPathComponent
        return parent.isEmpty ? "/" : parent
    }

    /// Whether we can move the file to the current path
    /// (can't move to the same directory it's already in).
    private var canMoveHere: Bool {
        currentPath != fileParent
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Breadcrumbs
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(Array(pathComponents.enumerated()), id: \.offset) { index, component in
                            if index > 0 {
                                Image(systemName: "chevron.right")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                            Button {
                                Task { await navigateTo(component.path) }
                            } label: {
                                Text(component.name == "/" ? "Root" : component.name)
                                    .font(.caption.weight(index == pathComponents.count - 1 ? .semibold : .regular))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                }

                Divider()

                // Folder list
                if isLoading {
                    Spacer()
                    ProgressView()
                    Spacer()
                } else if folders.isEmpty {
                    ContentUnavailableView {
                        Label("No Subfolders", systemImage: "folder")
                    } description: {
                        Text("This directory has no subfolders.")
                    }
                } else {
                    List(folders) { folder in
                        Button {
                            Task { await navigateTo(folder.path) }
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "folder.fill")
                                    .foregroundStyle(.yellow)
                                Text(folder.name)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Move \"\(file.name)\"")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Move Here") {
                        Task { await move() }
                    }
                    .disabled(!canMoveHere || isMoving)
                }
            }
            .interactiveDismissDisabled(isMoving)
        }
        .presentationDetents([.medium, .large])
        .task {
            await navigateTo("/")
        }
    }

    private func navigateTo(_ path: String) async {
        isLoading = true
        currentPath = path
        folders = await fetchFolders(path)
        isLoading = false
    }

    private func move() async {
        isMoving = true
        let success = await onMove(currentPath)
        isMoving = false

        if success {
            dismiss()
        }
    }
}
