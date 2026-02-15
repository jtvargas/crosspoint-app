import Foundation

/// Device service implementation for the Stock firmware (ESP32-based HTTP server).
/// Default IP: 192.168.3.3
nonisolated struct StockFirmwareService: DeviceService {
    let baseURL: URL
    
    /// Stock firmware does not support move/rename operations.
    var supportsMoveRename: Bool { false }
    
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
    
    init(ip: String = "192.168.3.3") {
        self.baseURL = URL(string: "http://\(ip)")!
    }
    
    func checkReachability() async -> Bool {
        let url = baseURL.appendingPathComponent("list")
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "dir", value: "/")]
        
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
        let url = baseURL.appendingPathComponent("list")
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "dir", value: directory)]
        
        guard let requestURL = components.url else { throw DeviceError.invalidResponse }
        
        let (data, _) = try await session.data(from: requestURL)
        
        guard let json = try JSONSerialization.jsonObject(with: data) as? [[String: String]] else {
            throw DeviceError.invalidResponse
        }
        
        return json.compactMap { entry in
            guard let name = entry["name"], let type = entry["type"] else { return nil }
            let isDirectory = type == "dir"
            let isEpub = !isDirectory && name.lowercased().hasSuffix(".epub")
            return DeviceFile(
                name: name,
                isDirectory: isDirectory,
                size: 0,
                isEpub: isEpub,
                parentPath: directory
            )
        }
    }
    
    func createFolder(name: String, parent: String) async throws {
        let url = baseURL.appendingPathComponent("edit")
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        
        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        let path = "\(parent)\(name)/"
        var body = Data()
        body.appendMultipartField(name: "path", value: path, boundary: boundary)
        body.appendMultipartEnd(boundary: boundary)
        request.httpBody = body
        
        let (_, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw DeviceError.folderCreationFailed
        }
    }
    
    func uploadFile(data: Data, filename: String, toFolder folder: String, progress: (@Sendable (Double) -> Void)?) async throws {
        let url = baseURL.appendingPathComponent("edit")
        var request = URLRequest(url: url, timeoutInterval: 120)
        request.httpMethod = "POST"
        
        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        // Stock firmware: filename includes the full path
        let fullPath = "/\(folder)/\(filename)"
        
        var body = Data()
        body.appendMultipartFile(
            name: "data",
            filename: fullPath,
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
        let url = baseURL.appendingPathComponent("edit")
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        
        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        var body = Data()
        body.appendMultipartField(name: "path", value: path, boundary: boundary)
        body.appendMultipartEnd(boundary: boundary)
        request.httpBody = body
        
        let (_, _) = try await session.data(for: request)
    }
    
    func deleteFolder(path: String) async throws {
        // Stock firmware uses the same DELETE /edit endpoint for both files and folders.
        let url = baseURL.appendingPathComponent("edit")
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        
        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        var body = Data()
        body.appendMultipartField(name: "path", value: path, boundary: boundary)
        body.appendMultipartEnd(boundary: boundary)
        request.httpBody = body
        
        let (_, _) = try await session.data(for: request)
    }
    
    func moveFile(path: String, destination: String) async throws {
        throw DeviceError.unsupportedOperation
    }
    
    func renameFile(path: String, newName: String) async throws {
        throw DeviceError.unsupportedOperation
    }
    
    func fetchStatus() async throws -> DeviceStatus {
        throw DeviceError.unsupportedOperation
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
/// Used by StockFirmwareService for progress-tracked uploads.
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
