import Foundation
import SwiftData

// MARK: - Supporting Enums

/// Broad category of activity — allows filtering and future expansion.
enum ActivityCategory: String, Codable, CaseIterable {
    case fileManager
    case wallpaper
    case queue
    case rss
}

/// Specific action performed within a category.
enum ActivityAction: String, Codable {
    // File Manager actions
    case upload
    case createFolder
    case moveFile
    case deleteFile
    case deleteFolder
    case wallpaperUpload
    case queueSend
    case rssConversion
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
        case .upload:          return "arrow.up.doc.fill"
        case .createFolder:    return "folder.badge.plus"
        case .moveFile:        return "arrow.right.doc.on.clipboard"
        case .deleteFile:      return "trash.fill"
        case .deleteFolder:    return "trash.fill"
        case .wallpaperUpload: return "photo.artframe"
        case .queueSend:       return "paperplane.circle.fill"
        case .rssConversion:   return "antenna.radiowaves.left.and.right"
        }
    }

    /// Human-readable action label.
    var actionLabel: String {
        switch action {
        case .upload:          return loc(.activityFileUploaded)
        case .createFolder:    return loc(.activityFolderCreated)
        case .moveFile:        return loc(.activityFileMoved)
        case .deleteFile:      return loc(.activityFileDeleted)
        case .deleteFolder:    return loc(.activityFolderDeleted)
        case .wallpaperUpload: return loc(.activityWallpaperSent)
        case .queueSend:       return loc(.activityQueueSent)
        case .rssConversion:   return loc(.activityRSSConversion)
        }
    }

    /// Human-readable category label.
    var categoryLabel: String {
        switch category {
        case .fileManager: return loc(.categoryFileManager)
        case .wallpaper:   return loc(.categoryWallpaper)
        case .queue:       return loc(.filterQueue)
        case .rss:         return loc(.categoryRSS)
        }
    }
}
