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
    func uploadFile(data: Data, filename: String, toFolder: String) async throws
    
    /// Delete a file from the device.
    func deleteFile(path: String) async throws
    
    /// Ensure the target folder exists, creating it if necessary.
    func ensureFolder(_ name: String) async throws
}

// Default implementation for ensureFolder
extension DeviceService {
    func ensureFolder(_ name: String) async throws {
        let files = try await listFiles(directory: "/")
        let exists = files.contains { $0.isDirectory && $0.name == name }
        if !exists {
            try await createFolder(name: name, parent: "/")
        }
    }
}
