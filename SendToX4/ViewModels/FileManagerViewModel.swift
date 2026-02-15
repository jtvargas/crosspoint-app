import Foundation
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

    /// Device status info (nil if not fetched or unsupported).
    var deviceStatus: DeviceStatus?

    /// Upload progress (nil when not uploading).
    var uploadProgress: Double?

    /// Name of file currently being uploaded.
    var uploadFilename: String?

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

    // MARK: - Service Binding

    /// Update the service reference (called when device connects/disconnects).
    func bind(to service: (any DeviceService)?) {
        let changed = (self.service?.baseURL.absoluteString != service?.baseURL.absoluteString)
        self.service = service
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
            errorMessage = "Not connected to device."
            files = []
            return
        }

        let targetPath = path ?? currentPath
        isLoading = true
        errorMessage = nil

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
    func createFolder(name: String) async -> Bool {
        guard let service else {
            errorMessage = "Not connected to device."
            return false
        }

        if let validationError = FileNameValidator.validate(name) {
            errorMessage = validationError
            return false
        }

        do {
            try await service.createFolder(name: name, parent: currentPath)
            await loadDirectory()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    /// Upload a file to the current directory.
    func uploadFile(data: Data, filename: String) async {
        guard let service else {
            errorMessage = "Not connected to device."
            return
        }

        uploadProgress = 0
        uploadFilename = filename

        // Determine the folder path for upload (strip leading "/" for the upload API)
        let folder = currentPath == "/" ? "" : String(currentPath.dropFirst())

        do {
            try await service.uploadFile(data: data, filename: filename, toFolder: folder) { [weak self] progress in
                Task { @MainActor [weak self] in
                    self?.uploadProgress = progress
                }
            }
            uploadProgress = nil
            uploadFilename = nil
            await loadDirectory()
        } catch {
            uploadProgress = nil
            uploadFilename = nil
            errorMessage = error.localizedDescription
        }
    }

    /// Delete a file or folder.
    func deleteItem(_ file: DeviceFile) async -> Bool {
        guard let service else {
            errorMessage = "Not connected to device."
            return false
        }

        do {
            if file.isDirectory {
                try await service.deleteFolder(path: file.path)
            } else {
                try await service.deleteFile(path: file.path)
            }
            await loadDirectory()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    /// Move a file to a destination folder.
    func moveFile(_ file: DeviceFile, to destination: String) async -> Bool {
        guard let service else {
            errorMessage = "Not connected to device."
            return false
        }

        do {
            try await service.moveFile(path: file.path, destination: destination)
            await loadDirectory()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    /// Rename a file.
    /// Validation is handled by RenameFileSheet before calling this method.
    func renameFile(_ file: DeviceFile, to newName: String) async -> Bool {
        guard let service else {
            errorMessage = "Not connected to device."
            return false
        }

        do {
            try await service.renameFile(path: file.path, newName: newName)
            await loadDirectory()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    // MARK: - Folder Listing (for Move picker)

    /// Fetch all folders from a given path (for the move destination picker).
    func fetchFolders(at path: String) async -> [DeviceFile] {
        guard let service else { return [] }
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
