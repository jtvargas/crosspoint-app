import Foundation
import SwiftData

// MARK: - Supporting Enums

/// Broad category of activity — allows filtering and future expansion.
enum ActivityCategory: String, Codable, CaseIterable {
    case fileManager
    // Future: case convert, case wallpaper, etc.
}

/// Specific action performed within a category.
enum ActivityAction: String, Codable {
    // File Manager actions
    case upload
    case createFolder
    case moveFile
    case deleteFile
    case deleteFolder
    // Future: case renameFile, case wallpaperUpload, etc.
}

/// Outcome of the activity.
enum ActivityStatus: String, Codable {
    case success
    case failed
}

// MARK: - ActivityEvent Model

/// Persisted record of a user action in the app (file manager operations, etc.).
/// Conversion history is stored separately in `Article` and merged at the view layer.
@Model
final class ActivityEvent {
    var id: UUID
    var timestamp: Date
    var categoryRaw: String
    var actionRaw: String
    var statusRaw: String
    var detail: String
    var errorMessage: String?

    // MARK: - Typed Accessors

    var category: ActivityCategory {
        get { ActivityCategory(rawValue: categoryRaw) ?? .fileManager }
        set { categoryRaw = newValue.rawValue }
    }

    var action: ActivityAction {
        get { ActivityAction(rawValue: actionRaw) ?? .upload }
        set { actionRaw = newValue.rawValue }
    }

    var status: ActivityStatus {
        get { ActivityStatus(rawValue: statusRaw) ?? .success }
        set { statusRaw = newValue.rawValue }
    }

    // MARK: - Init

    init(
        category: ActivityCategory,
        action: ActivityAction,
        status: ActivityStatus,
        detail: String,
        errorMessage: String? = nil
    ) {
        self.id = UUID()
        self.timestamp = Date()
        self.categoryRaw = category.rawValue
        self.actionRaw = action.rawValue
        self.statusRaw = status.rawValue
        self.detail = detail
        self.errorMessage = errorMessage
    }

    // MARK: - Icon Helpers

    /// SF Symbol name for this action type.
    var iconName: String {
        switch action {
        case .upload:       return "arrow.up.doc.fill"
        case .createFolder: return "folder.badge.plus"
        case .moveFile:     return "arrow.right.doc.on.clipboard"
        case .deleteFile:   return "trash.fill"
        case .deleteFolder: return "trash.fill"
        }
    }

    /// Icon color based on action and status.
    var iconColorName: String {
        if status == .failed { return "red" }
        switch action {
        case .upload:       return "blue"
        case .createFolder: return "yellow"
        case .moveFile:     return "purple"
        case .deleteFile:   return "orange"
        case .deleteFolder: return "orange"
        }
    }

    /// Human-readable action label.
    var actionLabel: String {
        switch action {
        case .upload:       return "File Uploaded"
        case .createFolder: return "Folder Created"
        case .moveFile:     return "File Moved"
        case .deleteFile:   return "File Deleted"
        case .deleteFolder: return "Folder Deleted"
        }
    }
}
