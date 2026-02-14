import Foundation

/// Represents a file or directory on the X4 device.
struct DeviceFile {
    let name: String
    let isDirectory: Bool
}

/// Errors for device communication.
enum DeviceError: LocalizedError {
    case unreachable
    case uploadFailed(statusCode: Int)
    case folderCreationFailed
    case invalidResponse
    case timeout
    case connectionLost
    
    var errorDescription: String? {
        switch self {
        case .unreachable:
            return "Cannot reach X4 device. Make sure you are connected to the X4 WiFi hotspot."
        case .uploadFailed(let code):
            return "Upload failed with status code \(code)."
        case .folderCreationFailed:
            return "Could not create folder on device."
        case .invalidResponse:
            return "Received an unexpected response from the device."
        case .timeout:
            return "Connection to the device timed out."
        case .connectionLost:
            return "The connection to the device was lost during upload. The file may be too large or the WiFi signal too weak. Please try again."
        }
    }
}

/// Protocol defining the interface for X4 device communication.
/// Both Stock and CrossPoint firmware implement this protocol.
protocol DeviceService: Sendable {
    var baseURL: URL { get }
    
    /// Check if the device is reachable.
    func checkReachability() async -> Bool
    
    /// List files in a directory on the device.
    func listFiles(directory: String) async throws -> [DeviceFile]
    
    /// Create a folder on the device.
    func createFolder(name: String, parent: String) async throws
    
    /// Upload an EPUB file to the device.
    /// - Parameters:
    ///   - data: The file data to upload.
    ///   - filename: The destination filename.
    ///   - toFolder: The destination folder on the device.
    ///   - progress: Optional callback reporting upload progress (0.0 to 1.0).
    func uploadFile(data: Data, filename: String, toFolder: String, progress: (@Sendable (Double) -> Void)?) async throws
    
    /// Delete a file from the device.
    func deleteFile(path: String) async throws
    
    /// Ensure the target folder exists, creating it if necessary.
    func ensureFolder(_ name: String) async throws
}

// Default implementations
extension DeviceService {
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
