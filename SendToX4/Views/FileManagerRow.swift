import SwiftUI

/// A single row in the file manager list representing a file or folder.
struct FileManagerRow: View {
    let file: DeviceFile
    let supportsMoveRename: Bool
    var onDelete: () -> Void
    var onMove: (() -> Void)?
    var onRename: (() -> Void)?

    var body: some View {
        HStack(spacing: 12) {
            // File/folder icon
            Image(systemName: iconName)
                .font(.title3)
                .foregroundStyle(iconColor)
                .frame(width: 28)

            // Name + size
            VStack(alignment: .leading, spacing: 2) {
                Text(file.name)
                    .font(.body)
                    .lineLimit(1)

                if !file.isDirectory && file.size > 0 {
                    Text(file.formattedSize)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            // Chevron for folders
            if file.isDirectory {
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            // Visible ellipsis menu for all items
            ellipsisMenu
        }
        .contentShape(Rectangle())
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                onDelete()
            } label: {
                Label(loc(.delete), systemImage: "trash")
            }

            if !file.isDirectory && supportsMoveRename {
                if let onMove {
                    Button {
                        onMove()
                    } label: {
                        Label(loc(.move), systemImage: "folder")
                    }
                    .tint(AppColor.accent)
                }
            }
        }
        .contextMenu {
            if !file.isDirectory && supportsMoveRename {
                Button { } label: {
                    Label(loc(.renameComingSoon), systemImage: "pencil")
                }
                .disabled(true)

                if let onMove {
                    Button {
                        onMove()
                    } label: {
                        Label(loc(.moveTo), systemImage: "folder")
                    }
                }

                Divider()
            }

            Button(role: .destructive) {
                onDelete()
            } label: {
                Label(loc(.delete), systemImage: "trash")
            }
        }
    }

    // MARK: - Ellipsis Menu

    private var ellipsisMenu: some View {
        Menu {
            if !file.isDirectory && supportsMoveRename {
                Button { } label: {
                    Label(loc(.renameComingSoon), systemImage: "pencil")
                }
                .disabled(true)

                if let onMove {
                    Button {
                        onMove()
                    } label: {
                        Label(loc(.moveTo), systemImage: "folder")
                    }
                }

                Divider()
            }

            Button(role: .destructive) {
                onDelete()
            } label: {
                Label(loc(.delete), systemImage: "trash")
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.body)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Icon Helpers

    private var iconName: String {
        if file.isDirectory {
            return "folder.fill"
        } else if file.isEpub {
            return "book.fill"
        } else {
            return "doc.fill"
        }
    }

    private var iconColor: Color {
        if file.isDirectory {
            return AppColor.accent
        } else if file.isEpub {
            return AppColor.accent
        } else {
            return .secondary
        }
    }
}
