import Foundation
import SwiftData
import UniformTypeIdentifiers

/// Manages file browsing, navigation, and file operations for the File Manager feature.
@MainActor
@Observable
final class FileManagerViewModel {

    // MARK: - State

    /// Current directory path being displayed (starts at "/").
    var currentPath: String = "/"

    /// Files in the current directory.
    var files: [DeviceFile] = []

    /// Whether files are currently being loaded.
    var isLoading = false

    /// Error message to display to user.
    var errorMessage: String?

    // MARK: - Recursive Delete State

    /// Whether a recursive folder deletion is in progress.
    var isDeleting = false

    /// Progress during recursive delete: (current 1-based index, total count).
    var deleteProgress: (current: Int, total: Int)?

    /// Name of the item currently being deleted.
    var currentDeleteItem: String?

    /// Number of items counted inside a folder (set after counting, before confirmation).
    var folderContentCount: Int?

    /// Whether we're currently counting folder contents.
    var isCountingContents = false

    /// Device status info (nil if not fetched or unsupported).
    var deviceStatus: DeviceStatus?

    /// Set to `true` when a review prompt should be shown. The View observes this.
    var shouldRequestReview = false

    /// Whether the connected firmware supports move/rename.
    var supportsMoveRename: Bool {
        service?.supportsMoveRename ?? false
    }

    /// Breadcrumb path components for navigation.
    /// For path "/content/subfolder" returns [("/", "/"), ("content", "/content"), ("subfolder", "/content/subfolder")].
    var pathComponents: [(name: String, path: String)] {
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

    /// Whether we're at the root directory.
    var isAtRoot: Bool { currentPath == "/" }

    // MARK: - Private

    private var service: (any DeviceService)?

    /// Weak reference to the device view model for operation tracking.
    /// The health ping suspends while any operation is in progress.
    private weak var deviceVM: DeviceViewModel?

    // MARK: - Service Binding

    /// Update the service reference and device view model (called when device connects/disconnects).
    func bind(to service: (any DeviceService)?, deviceVM: DeviceViewModel?) {
        let changed = (self.service?.baseURL.absoluteString != service?.baseURL.absoluteString)
        self.service = service
        self.deviceVM = deviceVM
        if changed {
            // Reset state when service changes
            currentPath = "/"
            files = []
            deviceStatus = nil
            errorMessage = nil
        }
    }

    // MARK: - Navigation

    /// Load files for the given directory path.
    func loadDirectory(_ path: String? = nil) async {
        guard let service else {
            errorMessage = loc(.notConnectedToDevice)
            files = []
            return
        }

        let targetPath = path ?? currentPath
        isLoading = true
        errorMessage = nil

        deviceVM?.beginOperation()
        defer { deviceVM?.endOperation() }

        do {
            let result = try await service.listFiles(directory: targetPath)
            currentPath = targetPath
            // Sort: directories first, then alphabetically within each group
            files = result.sorted { a, b in
                if a.isDirectory != b.isDirectory {
                    return a.isDirectory
                }
                return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
            }
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    /// Navigate into a subdirectory.
    func navigateTo(_ folder: DeviceFile) async {
        guard folder.isDirectory else { return }
        await loadDirectory(folder.path)
    }

    /// Navigate up to the parent directory.
    func navigateUp() async {
        guard !isAtRoot else { return }
        let parent = (currentPath as NSString).deletingLastPathComponent
        await loadDirectory(parent.isEmpty ? "/" : parent)
    }

    /// Navigate to a specific breadcrumb path.
    func navigateToBreadcrumb(_ path: String) async {
        await loadDirectory(path)
    }

    // MARK: - Status

    /// Fetch device status (silently fails for unsupported firmware).
    func refreshStatus() async {
        guard let service else { return }
        deviceVM?.beginOperation()
        defer { deviceVM?.endOperation() }
        do {
            deviceStatus = try await service.fetchStatus()
        } catch {
            // Silently ignore — Stock firmware doesn't support this
            deviceStatus = nil
        }
    }

    /// Full refresh: reload directory + status.
    func refresh() async {
        async let loadTask: () = loadDirectory()
        async let statusTask: () = refreshStatus()
        _ = await (loadTask, statusTask)
    }

    // MARK: - File Operations

    /// Create a new folder in the current directory.
    func createFolder(name: String, modelContext: ModelContext) async -> Bool {
        guard let service else {
            errorMessage = loc(.notConnectedToDevice)
            return false
        }

        if let validationError = FileNameValidator.validate(name) {
            errorMessage = validationError
            return false
        }

        deviceVM?.beginOperation()
        defer { deviceVM?.endOperation() }

        do {
            try await service.createFolder(name: name, parent: currentPath)
            logActivity(.createFolder, detail: loc(.createdFolderIn, name, currentPath), modelContext: modelContext)
            if ReviewPromptManager.shouldPromptAfterSuccess() {
                shouldRequestReview = true
            }
            await loadDirectory()
            return true
        } catch {
            logActivity(.createFolder, detail: loc(.failedToCreateFolderIn, name, currentPath), status: .failed, error: error, modelContext: modelContext)
            errorMessage = error.localizedDescription
            return false
        }
    }

    /// Upload a file to the current directory, routed through `DeviceViewModel`
    /// so that global upload state (progress, filename) is visible across all tabs.
    func uploadFile(data: Data, filename: String, deviceVM: DeviceViewModel, modelContext: ModelContext) async {
        // Determine the folder path for upload (strip leading "/" for the upload API)
        let folder = currentPath == "/" ? "" : String(currentPath.dropFirst())

        do {
            try await deviceVM.upload(data: data, filename: filename, toFolder: folder)
            logActivity(.upload, detail: loc(.uploadedFileTo, filename, currentPath), modelContext: modelContext)
            if ReviewPromptManager.shouldPromptAfterSuccess() {
                shouldRequestReview = true
            }
            await loadDirectory()
        } catch {
            logActivity(.upload, detail: loc(.failedToUploadFileTo, filename, currentPath), status: .failed, error: error, modelContext: modelContext)
            errorMessage = error.localizedDescription
        }
    }

    /// Delete a file or folder.
    /// For folders, attempts a simple delete first; if it fails with `.folderNotEmpty`,
    /// the caller should use `deleteItemRecursive` instead.
    func deleteItem(_ file: DeviceFile, modelContext: ModelContext) async -> Bool {
        guard let service else {
            errorMessage = loc(.notConnectedToDevice)
            return false
        }

        let action: ActivityAction = file.isDirectory ? .deleteFolder : .deleteFile

        deviceVM?.beginOperation()
        defer { deviceVM?.endOperation() }

        do {
            if file.isDirectory {
                try await service.deleteFolder(path: file.path)
            } else {
                try await service.deleteFile(path: file.path)
            }
            let detail = file.isDirectory
                ? loc(.deletedFolderFrom, currentPath, file.name)
                : loc(.deletedFileFrom, currentPath, file.name)
            logActivity(action, detail: detail, modelContext: modelContext)
            await loadDirectory()
            return true
        } catch {
            let detail = file.isDirectory
                ? loc(.failedToDeleteFolderFrom, currentPath, file.name)
                : loc(.failedToDeleteFileFrom, currentPath, file.name)
            logActivity(action, detail: detail, status: .failed, error: error, modelContext: modelContext)
            errorMessage = error.localizedDescription
            return false
        }
    }

    // MARK: - Recursive Folder Deletion

    /// Count all items (files + folders) inside a folder recursively.
    /// Sets `folderContentCount` and `isCountingContents` for UI binding.
    func countFolderContents(_ folder: DeviceFile) async -> Int {
        guard let service, folder.isDirectory else { return 0 }

        isCountingContents = true
        defer { isCountingContents = false }

        deviceVM?.beginOperation()
        defer { deviceVM?.endOperation() }

        let count = await recursiveCount(path: folder.path, service: service)
        folderContentCount = count
        return count
    }

    /// Recursively count all items under a path using the device service.
    private func recursiveCount(path: String, service: any DeviceService) async -> Int {
        guard let items = try? await service.listFiles(directory: path) else { return 0 }

        var count = items.count
        for item in items where item.isDirectory {
            count += await recursiveCount(path: item.path, service: service)
        }
        return count
    }

    /// Delete a folder and all its contents recursively with progress feedback.
    ///
    /// Strategy: depth-first traversal — delete files in each directory first,
    /// then recurse into subdirectories, then delete the now-empty directory.
    /// This is efficient because it minimizes API calls (one listFiles per directory)
    /// and deletes leaves before branches.
    func deleteItemRecursive(_ folder: DeviceFile, totalCount: Int, modelContext: ModelContext) async -> Bool {
        guard let service, folder.isDirectory else {
            errorMessage = loc(.notConnectedToDevice)
            return false
        }

        isDeleting = true
        deleteProgress = (0, totalCount + 1) // +1 for the folder itself
        currentDeleteItem = nil
        errorMessage = nil

        deviceVM?.beginOperation()

        var deletedCount = 0

        let success = await recursiveDelete(
            path: folder.path,
            service: service,
            totalCount: totalCount + 1,
            deletedCount: &deletedCount
        )

        // Now delete the top-level folder itself (should be empty now)
        if success {
            do {
                deletedCount += 1
                deleteProgress = (deletedCount, totalCount + 1)
                currentDeleteItem = folder.name
                try await service.deleteFolder(path: folder.path)
            } catch {
                // Folder delete failed — partial cleanup happened
                let detail = loc(.failedToDeleteFolderRecursive, currentPath, folder.name, deletedCount - 1, totalCount)
                logActivity(.deleteFolder, detail: detail, status: .failed, error: error, modelContext: modelContext)
                errorMessage = error.localizedDescription
                cleanupDeleteState()
                deviceVM?.endOperation()
                await loadDirectory()
                return false
            }
        }

        deviceVM?.endOperation()

        if success {
            let detail = loc(.deletedFolderRecursive, folder.name, totalCount, currentPath)
            logActivity(.deleteFolder, detail: detail, modelContext: modelContext)
            if ReviewPromptManager.shouldPromptAfterSuccess() {
                shouldRequestReview = true
            }
        } else {
            let detail = loc(.failedToDeleteFolderRecursive, currentPath, folder.name, deletedCount, totalCount)
            logActivity(.deleteFolder, detail: detail, status: .failed, modelContext: modelContext)
        }

        cleanupDeleteState()
        await loadDirectory()
        return success
    }

    /// Depth-first recursive delete of all contents under a path.
    /// Returns `true` if all items were deleted successfully.
    private func recursiveDelete(
        path: String,
        service: any DeviceService,
        totalCount: Int,
        deletedCount: inout Int
    ) async -> Bool {
        guard let items = try? await service.listFiles(directory: path) else { return false }

        // Separate files and directories
        let files = items.filter { !$0.isDirectory }
        let directories = items.filter { $0.isDirectory }

        // Delete all files first (leaves)
        for file in files {
            deletedCount += 1
            deleteProgress = (deletedCount, totalCount)
            currentDeleteItem = file.name

            do {
                try await service.deleteFile(path: file.path)
            } catch {
                errorMessage = error.localizedDescription
                return false
            }

            // Brief cooldown to avoid overwhelming the ESP32
            try? await Task.sleep(for: .milliseconds(100))
        }

        // Recurse into subdirectories (depth-first)
        for dir in directories {
            let childSuccess = await recursiveDelete(
                path: dir.path,
                service: service,
                totalCount: totalCount,
                deletedCount: &deletedCount
            )

            guard childSuccess else { return false }

            // Delete the now-empty subdirectory
            deletedCount += 1
            deleteProgress = (deletedCount, totalCount)
            currentDeleteItem = dir.name

            do {
                try await service.deleteFolder(path: dir.path)
            } catch {
                errorMessage = error.localizedDescription
                return false
            }

            try? await Task.sleep(for: .milliseconds(100))
        }

        return true
    }

    /// Reset all recursive delete state.
    private func cleanupDeleteState() {
        isDeleting = false
        deleteProgress = nil
        currentDeleteItem = nil
        folderContentCount = nil
    }

    /// Move a file to a destination folder.
    func moveFile(_ file: DeviceFile, to destination: String, modelContext: ModelContext) async -> Bool {
        guard let service else {
            errorMessage = loc(.notConnectedToDevice)
            return false
        }

        deviceVM?.beginOperation()
        defer { deviceVM?.endOperation() }

        do {
            try await service.moveFile(path: file.path, destination: destination)
            logActivity(.moveFile, detail: loc(.movedFileTo, file.name, destination), modelContext: modelContext)
            await loadDirectory()
            return true
        } catch {
            logActivity(.moveFile, detail: loc(.failedToMoveFileTo, file.name, destination), status: .failed, error: error, modelContext: modelContext)
            errorMessage = error.localizedDescription
            return false
        }
    }

    /// Rename a file.
    /// Validation is handled by RenameFileSheet before calling this method.
    func renameFile(_ file: DeviceFile, to newName: String) async -> Bool {
        guard let service else {
            errorMessage = loc(.notConnectedToDevice)
            return false
        }

        deviceVM?.beginOperation()
        defer { deviceVM?.endOperation() }

        do {
            try await service.renameFile(path: file.path, newName: newName)
            await loadDirectory()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    // MARK: - Activity Logging

    /// Log a file manager activity event to SwiftData.
    private func logActivity(
        _ action: ActivityAction,
        detail: String,
        status: ActivityStatus = .success,
        error: Error? = nil,
        modelContext: ModelContext
    ) {
        let event = ActivityEvent(
            category: .fileManager,
            action: action,
            status: status,
            detail: detail,
            errorMessage: error?.localizedDescription
        )
        modelContext.insert(event)
    }

    // MARK: - Folder Listing (for Move picker)

    /// Fetch all folders from a given path (for the move destination picker).
    func fetchFolders(at path: String) async -> [DeviceFile] {
        guard let service else { return [] }
        deviceVM?.beginOperation()
        defer { deviceVM?.endOperation() }
        do {
            let items = try await service.listFiles(directory: path)
            return items
                .filter(\.isDirectory)
                .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        } catch {
            return []
        }
    }
}
