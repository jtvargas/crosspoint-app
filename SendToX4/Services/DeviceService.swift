import Foundation

// MARK: - Models

/// Represents a file or directory on the X4 device.
nonisolated struct DeviceFile: Identifiable, Equatable {
    let name: String
    let isDirectory: Bool
    let size: Int64
    let isEpub: Bool
    /// Full path on the device (e.g. "/content/book.epub").
    let path: String

    var id: String { path }

    /// File size formatted for display (e.g. "1.2 MB", "340 KB").
    var formattedSize: String {
        guard !isDirectory else { return "" }
        if size < 1024 {
            return "\(size) B"
        } else if size < 1024 * 1024 {
            return String(format: "%.1f KB", Double(size) / 1024.0)
        } else {
            return String(format: "%.1f MB", Double(size) / (1024.0 * 1024.0))
        }
    }

    init(name: String, isDirectory: Bool, size: Int64 = 0, isEpub: Bool = false, parentPath: String = "/") {
        self.name = name
        self.isDirectory = isDirectory
        self.size = size
        self.isEpub = isEpub
        let parent = parentPath.hasSuffix("/") ? parentPath : parentPath + "/"
        self.path = parent + name
    }
}

/// Device status information (CrossPoint firmware).
nonisolated struct DeviceStatus {
    let version: String
    let ip: String
    let mode: String       // "STA" or "AP"
    let rssi: Int          // Signal strength (0 in AP mode)
    let freeHeap: Int      // Free memory in bytes
    let uptime: Int        // Seconds since boot

    /// Uptime formatted as "Xh Ym" or "Xm".
    var formattedUptime: String {
        let hours = uptime / 3600
        let minutes = (uptime % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }

    /// WiFi mode display label.
    var modeLabel: String {
        mode == "AP" ? loc(.accessPoint) : loc(.stationMode)
    }
}

// MARK: - Errors

/// Errors for device communication.
nonisolated enum DeviceError: LocalizedError {
    case unreachable
    case uploadFailed(statusCode: Int)
    case folderCreationFailed
    case invalidResponse
    case timeout
    case connectionLost
    case deleteFailed(String)
    case moveFailed(String)
    case renameFailed(String)
    case folderNotEmpty
    case itemAlreadyExists
    case protectedItem
    case unsupportedOperation

    var errorDescription: String? {
        switch self {
        case .unreachable:
            return loc(.errorCannotReachDevice)
        case .uploadFailed(let code):
            return loc(.errorUploadFailed, code)
        case .folderCreationFailed:
            return loc(.errorCreateFolderFailed)
        case .invalidResponse:
            return loc(.errorUnexpectedResponse)
        case .timeout:
            return loc(.errorTimeout)
        case .connectionLost:
            return loc(.errorConnectionLostDuringUpload)
        case .deleteFailed(let message):
            return loc(.errorDeleteFailed, message)
        case .moveFailed(let message):
            return loc(.errorMoveFailed, message)
        case .renameFailed(let message):
            return loc(.errorRenameFailed, message)
        case .folderNotEmpty:
            return loc(.errorFolderNotEmpty)
        case .itemAlreadyExists:
            return loc(.errorNameAlreadyExists)
        case .protectedItem:
            return loc(.errorItemProtected)
        case .unsupportedOperation:
            return loc(.errorOperationNotSupported)
        }
    }
}

// MARK: - Protocol

/// Protocol defining the interface for X4 device communication.
/// Both Stock and CrossPoint firmware implement this protocol.
nonisolated protocol DeviceService: Sendable {
    var baseURL: URL { get }

    /// Check if the device is reachable.
    func checkReachability() async -> Bool

    /// List files in a directory on the device.
    func listFiles(directory: String) async throws -> [DeviceFile]

    /// Create a folder on the device.
    func createFolder(name: String, parent: String) async throws

    /// Upload a file to the device.
    /// - Parameters:
    ///   - data: The file data to upload.
    ///   - filename: The destination filename.
    ///   - toFolder: The destination folder on the device.
    ///   - progress: Optional callback reporting upload progress (0.0 to 1.0).
    func uploadFile(data: Data, filename: String, toFolder: String, progress: (@Sendable (Double) -> Void)?) async throws

    /// Delete a file from the device.
    func deleteFile(path: String) async throws

    /// Delete an empty folder from the device.
    func deleteFolder(path: String) async throws

    /// Move a file to a different folder.
    /// - Parameters:
    ///   - path: Full path of the file to move.
    ///   - destination: Destination directory path.
    func moveFile(path: String, destination: String) async throws

    /// Rename a file.
    /// - Parameters:
    ///   - path: Full path of the file to rename.
    ///   - newName: The new filename.
    func renameFile(path: String, newName: String) async throws

    /// Fetch device status information.
    func fetchStatus() async throws -> DeviceStatus

    /// Ensure the target folder exists, creating it if necessary.
    func ensureFolder(_ name: String) async throws

    /// Whether this firmware supports move/rename operations.
    var supportsMoveRename: Bool { get }
}

// MARK: - Default Implementations

nonisolated extension DeviceService {
    func ensureFolder(_ name: String) async throws {
        let files = try await listFiles(directory: "/")
        let exists = files.contains { $0.isDirectory && $0.name == name }
        if !exists {
            try await createFolder(name: name, parent: "/")
        }
    }

    /// Convenience overload without progress callback.
    func uploadFile(data: Data, filename: String, toFolder folder: String) async throws {
        try await uploadFile(data: data, filename: filename, toFolder: folder, progress: nil)
    }
}

// MARK: - File Name Validation

nonisolated enum FileNameValidator {
    /// Characters forbidden in file/folder names on the device.
    private static let invalidCharacters: Set<Character> = [
        "\"", "*", ":", "<", ">", "?", "/", "\\", "|"
    ]

    /// Validate a file or folder name.
    /// Returns nil if valid, or an error message string if invalid.
    static func validate(_ name: String) -> String? {
        let trimmed = name.trimmingCharacters(in: .whitespaces)

        if trimmed.isEmpty {
            return loc(.validatorNameEmpty)
        }

        if trimmed == "." || trimmed == ".." {
            return loc(.validatorNameDotOrDotDot)
        }

        if trimmed.hasPrefix(".") {
            return loc(.validatorNameStartsWithDot)
        }

        if trimmed.contains(where: { invalidCharacters.contains($0) }) {
            return loc(.validatorNameInvalidCharacters)
        }

        return nil
    }
}
