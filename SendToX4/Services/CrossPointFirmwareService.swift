import Foundation

/// Device service implementation for the CrossPoint firmware.
/// Supports both mDNS hostname (crosspoint.local) and static IP (192.168.4.1).
nonisolated struct CrossPointFirmwareService: DeviceService {
    
    /// mDNS hostname — preferred, resolved via Bonjour.
    static let localHostname = "crosspoint.local"
    /// Static IP fallback when mDNS is unavailable.
    static let defaultIP = "192.168.4.1"
    
    let baseURL: URL
    
    /// URLSession with generous timeouts for large file uploads over slow ESP32 WiFi.
    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 120
        return URLSession(configuration: config)
    }()
    
    /// Maximum number of retry attempts for connection-lost errors.
    private static let maxRetries = 2
    /// Delay between retry attempts (in seconds).
    private static let retryDelay: UInt64 = 1_000_000_000 // 1 second in nanoseconds
    
    /// CrossPoint firmware supports move and rename operations.
    var supportsMoveRename: Bool { true }
    
    init(host: String = CrossPointFirmwareService.defaultIP) {
        self.baseURL = URL(string: "http://\(host)")!
    }
    
    func checkReachability() async -> Bool {
        let url = baseURL.appendingPathComponent("api/files")
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "path", value: "/")]
        
        guard let requestURL = components.url else { return false }
        
        var request = URLRequest(url: requestURL, timeoutInterval: 3)
        request.httpMethod = "GET"
        
        do {
            let (_, response) = try await session.data(for: request)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }
    
    func listFiles(directory: String) async throws -> [DeviceFile] {
        let url = baseURL.appendingPathComponent("api/files")
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "path", value: directory)]
        
        guard let requestURL = components.url else { throw DeviceError.invalidResponse }
        
        let (data, _) = try await session.data(from: requestURL)
        
        guard let json = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw DeviceError.invalidResponse
        }
        
        return json.compactMap { entry in
            guard let name = entry["name"] as? String,
                  let isDir = entry["isDirectory"] as? Bool else { return nil }
            let size = entry["size"] as? Int64 ?? 0
            let isEpub = entry["isEpub"] as? Bool ?? false
            return DeviceFile(name: name, isDirectory: isDir, size: size, isEpub: isEpub, parentPath: directory)
        }
    }
    
    func createFolder(name: String, parent: String) async throws {
        let url = baseURL.appendingPathComponent("mkdir")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        
        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        var body = Data()
        body.appendMultipartField(name: "name", value: name, boundary: boundary)
        body.appendMultipartField(name: "path", value: parent, boundary: boundary)
        body.appendMultipartEnd(boundary: boundary)
        request.httpBody = body
        
        let (data, response) = try await session.data(for: request)
        if let httpResponse = response as? HTTPURLResponse, !(200...299).contains(httpResponse.statusCode) {
            // 409 Conflict means the folder already exists — our goal is met
            if httpResponse.statusCode == 409 { return }
            let bodyText = String(data: data, encoding: .utf8) ?? "Unknown error"
            switch httpResponse.statusCode {
            case 403:
                throw DeviceError.protectedItem
            default:
                throw DeviceError.folderCreationFailed(bodyText)
            }
        }
    }
    
    func uploadFile(data: Data, filename: String, toFolder folder: String, progress: (@Sendable (Double) -> Void)?) async throws {
        // CrossPoint: path is a query parameter, filename is just the name
        var components = URLComponents(url: baseURL.appendingPathComponent("upload"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "path", value: "/\(folder)")]
        
        guard let url = components.url else { throw DeviceError.invalidResponse }
        
        var request = URLRequest(url: url, timeoutInterval: 120)
        request.httpMethod = "POST"
        
        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        var body = Data()
        body.appendMultipartFile(
            name: "file",
            filename: filename,
            mimeType: "application/epub+zip",
            data: data,
            boundary: boundary
        )
        body.appendMultipartEnd(boundary: boundary)
        
        // Retry logic for connection-lost errors
        for attempt in 0...Self.maxRetries {
            do {
                let (_, response) = try await uploadWithProgress(
                    request: request,
                    body: body,
                    progress: progress
                )
                guard let httpResponse = response as? HTTPURLResponse,
                      (200...299).contains(httpResponse.statusCode) else {
                    let code = (response as? HTTPURLResponse)?.statusCode ?? 0
                    throw DeviceError.uploadFailed(statusCode: code)
                }
                return // Success
            } catch let error as NSError where error.code == NSURLErrorNetworkConnectionLost {
                if attempt < Self.maxRetries {
                    try await Task.sleep(nanoseconds: Self.retryDelay)
                    progress?(0) // Reset progress for retry
                }
            } catch {
                throw error // Non-retryable error
            }
        }
        
        // All retries exhausted
        throw DeviceError.connectionLost
    }
    
    func deleteFile(path: String) async throws {
        let url = baseURL.appendingPathComponent("delete")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        
        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        var body = Data()
        body.appendMultipartField(name: "path", value: path, boundary: boundary)
        body.appendMultipartField(name: "type", value: "file", boundary: boundary)
        body.appendMultipartEnd(boundary: boundary)
        request.httpBody = body
        
        let (_, _) = try await session.data(for: request)
    }
    
    func deleteFolder(path: String) async throws {
        let url = baseURL.appendingPathComponent("delete")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        
        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        var body = Data()
        body.appendMultipartField(name: "path", value: path, boundary: boundary)
        body.appendMultipartField(name: "type", value: "folder", boundary: boundary)
        body.appendMultipartEnd(boundary: boundary)
        request.httpBody = body
        
        let (data, response) = try await session.data(for: request)
        
        if let httpResponse = response as? HTTPURLResponse, !(200...299).contains(httpResponse.statusCode) {
            let bodyText = String(data: data, encoding: .utf8) ?? "Unknown error"
            switch httpResponse.statusCode {
            case 400:
                if bodyText.contains("not empty") {
                    throw DeviceError.folderNotEmpty
                }
                throw DeviceError.deleteFailed(bodyText)
            case 403:
                throw DeviceError.protectedItem
            case 404:
                throw DeviceError.deleteFailed("Item not found")
            default:
                throw DeviceError.deleteFailed(bodyText)
            }
        }
    }
    
    func moveFile(path: String, destination: String) async throws {
        let url = baseURL.appendingPathComponent("move")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        
        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        var body = Data()
        body.appendMultipartField(name: "path", value: path, boundary: boundary)
        body.appendMultipartField(name: "dest", value: destination, boundary: boundary)
        body.appendMultipartEnd(boundary: boundary)
        request.httpBody = body
        
        let (data, response) = try await session.data(for: request)
        
        if let httpResponse = response as? HTTPURLResponse, !(200...299).contains(httpResponse.statusCode) {
            let bodyText = String(data: data, encoding: .utf8) ?? "Unknown error"
            switch httpResponse.statusCode {
            case 400:
                throw DeviceError.moveFailed(bodyText)
            case 403:
                throw DeviceError.protectedItem
            case 404:
                throw DeviceError.moveFailed("Item not found")
            case 409:
                throw DeviceError.itemAlreadyExists
            default:
                throw DeviceError.moveFailed(bodyText)
            }
        }
    }
    
    func renameFile(path: String, newName: String) async throws {
        let url = baseURL.appendingPathComponent("rename")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        
        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        var body = Data()
        body.appendMultipartField(name: "path", value: path, boundary: boundary)
        body.appendMultipartField(name: "name", value: newName, boundary: boundary)
        body.appendMultipartEnd(boundary: boundary)
        request.httpBody = body
        
        let (data, response) = try await session.data(for: request)
        
        if let httpResponse = response as? HTTPURLResponse, !(200...299).contains(httpResponse.statusCode) {
            let bodyText = String(data: data, encoding: .utf8) ?? "Unknown error"
            switch httpResponse.statusCode {
            case 400:
                throw DeviceError.renameFailed(bodyText)
            case 403:
                throw DeviceError.protectedItem
            case 404:
                throw DeviceError.renameFailed("Item not found")
            case 409:
                throw DeviceError.itemAlreadyExists
            default:
                throw DeviceError.renameFailed(bodyText)
            }
        }
    }
    
    func fetchStatus() async throws -> DeviceStatus {
        let url = baseURL.appendingPathComponent("api/status")
        let (data, response) = try await session.data(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw DeviceError.invalidResponse
        }
        
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let version = json["version"] as? String,
              let ip = json["ip"] as? String,
              let mode = json["mode"] as? String,
              let rssi = json["rssi"] as? Int,
              let freeHeap = json["freeHeap"] as? Int,
              let uptime = json["uptime"] as? Int else {
            throw DeviceError.invalidResponse
        }
        
        return DeviceStatus(
            version: version,
            ip: ip,
            mode: mode,
            rssi: rssi,
            freeHeap: freeHeap,
            uptime: uptime
        )
    }
    
    // MARK: - Upload with Progress
    
    /// Performs the upload using URLSession.upload and observes progress via a delegate.
    private func uploadWithProgress(
        request: URLRequest,
        body: Data,
        progress: (@Sendable (Double) -> Void)?
    ) async throws -> (Data, URLResponse) {
        if let progress {
            let delegate = UploadProgressDelegate(progressHandler: progress)
            let task = session.uploadTask(with: request, from: body)
            
            return try await withCheckedThrowingContinuation { continuation in
                delegate.continuation = continuation
                task.delegate = delegate
                task.resume()
            }
        } else {
            // No progress needed — use simple upload
            return try await session.upload(for: request, from: body)
        }
    }
}

// MARK: - Upload Progress Delegate

/// URLSession task delegate that reports upload progress and captures the response.
private nonisolated final class UploadProgressDelegate: NSObject, URLSessionTaskDelegate, URLSessionDataDelegate, @unchecked Sendable {
    let progressHandler: @Sendable (Double) -> Void
    var continuation: CheckedContinuation<(Data, URLResponse), Error>?
    private var receivedData = Data()
    
    init(progressHandler: @escaping @Sendable (Double) -> Void) {
        self.progressHandler = progressHandler
    }
    
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didSendBodyData bytesSent: Int64,
        totalBytesSent: Int64,
        totalBytesExpectedToSend: Int64
    ) {
        guard totalBytesExpectedToSend > 0 else { return }
        let fraction = Double(totalBytesSent) / Double(totalBytesExpectedToSend)
        progressHandler(min(fraction, 1.0))
    }
    
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        receivedData.append(data)
    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error {
            continuation?.resume(throwing: error)
        } else if let response = task.response {
            continuation?.resume(returning: (receivedData, response))
        } else {
            continuation?.resume(throwing: DeviceError.invalidResponse)
        }
        continuation = nil
    }
}

// MARK: - Multipart Form Data Helpers

nonisolated extension Data {
    /// Append a text field to a multipart form body.
    mutating func appendMultipartField(name: String, value: String, boundary: String) {
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
        append("\(value)\r\n")
    }
    
    /// Append a file field to a multipart form body.
    mutating func appendMultipartFile(name: String, filename: String, mimeType: String, data: Data, boundary: String) {
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n")
        append("Content-Type: \(mimeType)\r\n\r\n")
        append(data)
        append("\r\n")
    }
    
    /// Append the closing boundary for a multipart form body.
    mutating func appendMultipartEnd(boundary: String) {
        append("--\(boundary)--\r\n")
    }
    
    /// Append a string as UTF-8 data.
    mutating func append(_ string: String) {
        if let data = string.data(using: .utf8) {
            append(data)
        }
    }
}
