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

    /// Maximum retry attempts per individual delete or listFiles operation.
    private static let maxDeleteRetries = 2
    /// Delay before retrying a failed delete operation.
    private static let deleteRetryDelay: Duration = .seconds(1)
    /// Cooldown between sequential delete operations to let the ESP32 recover.
    private static let deleteCooldown: Duration = .milliseconds(300)
    /// Number of consecutive failures before aborting the batch (device probably gone).
    private static let deleteCircuitBreakerThreshold = 3

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
    /// Retries `listFiles` up to `maxDeleteRetries` times per directory.
    private func recursiveCount(path: String, service: any DeviceService) async -> Int {
        guard let items = await listFilesWithRetry(path: path, service: service) else { return 0 }

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
    /// Each operation has retry logic (2 retries, 1s delay) and a circuit breaker
    /// (3 consecutive failures = abort) to handle ESP32 WiFi instability.
    /// Individual item failures are logged and skipped — the delete continues
    /// with remaining items unless the circuit breaker trips.
    func deleteItemRecursive(_ folder: DeviceFile, totalCount: Int, modelContext: ModelContext) async -> Bool {
        guard let service, folder.isDirectory else {
            errorMessage = loc(.notConnectedToDevice)
            return false
        }

        let totalWithFolder = totalCount + 1 // +1 for the folder itself

        isDeleting = true
        deleteProgress = (0, totalWithFolder)
        currentDeleteItem = nil
        errorMessage = nil

        deviceVM?.beginOperation()

        var deletedCount = 0
        var consecutiveFailures = 0
        var skippedItems: [String] = []

        DebugLogger.log(
            "Recursive delete started: \(folder.name) (\(totalCount) items)",
            level: .info, category: .device
        )

        let contentsCleared = await recursiveDelete(
            path: folder.path,
            service: service,
            totalCount: totalWithFolder,
            deletedCount: &deletedCount,
            consecutiveFailures: &consecutiveFailures,
            skippedItems: &skippedItems
        )

        // Attempt to delete the top-level folder itself
        var folderDeleted = false
        if contentsCleared || skippedItems.isEmpty {
            // All contents removed (or folder was already empty) — safe to delete
            deletedCount += 1
            deleteProgress = (deletedCount, totalWithFolder)
            currentDeleteItem = folder.name
            folderDeleted = await deleteWithRetry(service: service, isDirectory: true, path: folder.path)
            if !folderDeleted {
                DebugLogger.log(
                    "Failed to delete top-level folder: \(folder.path)",
                    level: .error, category: .device
                )
            }
        } else if !skippedItems.isEmpty {
            // Some items failed — try deleting the folder anyway (it may work if
            // the skipped items were files the device already removed)
            deletedCount += 1
            deleteProgress = (deletedCount, totalWithFolder)
            currentDeleteItem = folder.name
            folderDeleted = await deleteWithRetry(service: service, isDirectory: true, path: folder.path)
        }

        deviceVM?.endOperation()

        // Log results
        let failedCount = skippedItems.count + (folderDeleted ? 0 : 1)
        let successCount = deletedCount - failedCount

        if failedCount == 0 {
            // Complete success
            let detail = loc(.deletedFolderRecursive, folder.name, totalCount, currentPath)
            logActivity(.deleteFolder, detail: detail, modelContext: modelContext)
            DebugLogger.log(
                "Recursive delete complete: \(folder.name) — \(successCount) items deleted",
                level: .info, category: .device
            )
            if ReviewPromptManager.shouldPromptAfterSuccess() {
                shouldRequestReview = true
            }
        } else if contentsCleared || folderDeleted {
            // Partial success — some items failed but the folder was deleted
            let detail = loc(.deletedFolderRecursivePartial, folder.name, successCount, currentPath, failedCount)
            logActivity(.deleteFolder, detail: detail, status: .failed, modelContext: modelContext)
            DebugLogger.log(
                "Recursive delete partial: \(folder.name) — \(successCount) deleted, \(failedCount) failed",
                level: .warning, category: .device
            )
        } else {
            // Total failure — circuit breaker tripped or couldn't clear contents
            let detail = loc(.failedToDeleteFolderRecursive, currentPath, folder.name, successCount, totalCount)
            logActivity(.deleteFolder, detail: detail, status: .failed, modelContext: modelContext)
            DebugLogger.log(
                "Recursive delete failed: \(folder.name) — aborted after \(successCount) of \(totalCount) items",
                level: .error, category: .device
            )
        }

        cleanupDeleteState()
        await loadDirectory()
        return failedCount == 0
    }

    /// Depth-first recursive delete of all contents under a path.
    ///
    /// Returns `true` if the recursive traversal completed (even with some skipped items).
    /// Returns `false` only if the circuit breaker tripped or listing failed.
    /// Individual item failures are logged and skipped — the traversal continues.
    private func recursiveDelete(
        path: String,
        service: any DeviceService,
        totalCount: Int,
        deletedCount: inout Int,
        consecutiveFailures: inout Int,
        skippedItems: inout [String]
    ) async -> Bool {

        // List directory contents with retry
        guard let items = await listFilesWithRetry(path: path, service: service) else {
            DebugLogger.log(
                "Failed to list directory after retries: \(path)",
                level: .error, category: .device
            )
            errorMessage = loc(.errorUnexpectedResponse)
            return false
        }

        // Separate files and directories
        let files = items.filter { !$0.isDirectory }
        let directories = items.filter { $0.isDirectory }

        // Delete all files first (leaves)
        for file in files {
            // Circuit breaker: abort if too many consecutive failures
            if consecutiveFailures >= Self.deleteCircuitBreakerThreshold {
                DebugLogger.log(
                    "Circuit breaker tripped after \(consecutiveFailures) consecutive failures. Aborting recursive delete.",
                    level: .error, category: .device
                )
                errorMessage = loc(.queueCircuitBreaker, consecutiveFailures)
                return false
            }

            deletedCount += 1
            deleteProgress = (deletedCount, totalCount)
            currentDeleteItem = file.name

            let success = await deleteWithRetry(service: service, isDirectory: false, path: file.path)
            if success {
                consecutiveFailures = 0
            } else {
                consecutiveFailures += 1
                skippedItems.append(file.path)
                DebugLogger.log(
                    "Skipped file (delete failed after retries): \(file.path)",
                    level: .error, category: .device
                )
                // Continue to next item instead of aborting
            }

            // Cooldown to let the ESP32 recover between operations
            try? await Task.sleep(for: Self.deleteCooldown)
        }

        // Recurse into subdirectories (depth-first)
        for dir in directories {
            // Circuit breaker check before recursing
            if consecutiveFailures >= Self.deleteCircuitBreakerThreshold {
                DebugLogger.log(
                    "Circuit breaker tripped after \(consecutiveFailures) consecutive failures. Aborting recursive delete.",
                    level: .error, category: .device
                )
                errorMessage = loc(.queueCircuitBreaker, consecutiveFailures)
                return false
            }

            let childCompleted = await recursiveDelete(
                path: dir.path,
                service: service,
                totalCount: totalCount,
                deletedCount: &deletedCount,
                consecutiveFailures: &consecutiveFailures,
                skippedItems: &skippedItems
            )

            // If child aborted (circuit breaker), propagate the abort
            guard childCompleted else { return false }

            // Delete the now-empty subdirectory
            deletedCount += 1
            deleteProgress = (deletedCount, totalCount)
            currentDeleteItem = dir.name

            let folderDeleted = await deleteWithRetry(service: service, isDirectory: true, path: dir.path)
            if folderDeleted {
                consecutiveFailures = 0
            } else {
                consecutiveFailures += 1
                skippedItems.append(dir.path)
                DebugLogger.log(
                    "Skipped folder (delete failed after retries): \(dir.path)",
                    level: .error, category: .device
                )
            }

            try? await Task.sleep(for: Self.deleteCooldown)
        }

        return true
    }

    /// List files in a directory with retry logic.
    /// Returns `nil` if all retries are exhausted.
    private func listFilesWithRetry(path: String, service: any DeviceService) async -> [DeviceFile]? {
        for attempt in 0...Self.maxDeleteRetries {
            do {
                return try await service.listFiles(directory: path)
            } catch {
                if attempt < Self.maxDeleteRetries {
                    DebugLogger.log(
                        "listFiles retry \(attempt + 1)/\(Self.maxDeleteRetries) for \(path): \(error.localizedDescription)",
                        level: .warning, category: .device
                    )
                    try? await Task.sleep(for: Self.deleteRetryDelay)
                } else {
                    DebugLogger.log(
                        "listFiles failed after all retries for \(path): \(error.localizedDescription)",
                        level: .error, category: .device
                    )
                }
            }
        }
        return nil
    }

    /// Attempt to delete a single file or folder with retry logic.
    /// Returns `true` on success, `false` after all retries are exhausted.
    private func deleteWithRetry(service: any DeviceService, isDirectory: Bool, path: String) async -> Bool {
        let kind = isDirectory ? "folder" : "file"

        for attempt in 0...Self.maxDeleteRetries {
            do {
                if isDirectory {
                    try await service.deleteFolder(path: path)
                } else {
                    try await service.deleteFile(path: path)
                }
                return true
            } catch {
                if attempt < Self.maxDeleteRetries {
                    DebugLogger.log(
                        "Delete \(kind) retry \(attempt + 1)/\(Self.maxDeleteRetries) for \(path): \(error.localizedDescription)",
                        level: .warning, category: .device
                    )
                    try? await Task.sleep(for: Self.deleteRetryDelay)
                } else {
                    DebugLogger.log(
                        "Delete \(kind) failed after all retries: \(path) — \(error.localizedDescription)",
                        level: .error, category: .device
                    )
                    errorMessage = error.localizedDescription
                }
            }
        }
        return false
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
