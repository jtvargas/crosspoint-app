import Foundation

/// Device service implementation for the CrossPoint firmware.
/// Supports both mDNS hostname (crosspoint.local) and static IP (192.168.4.1).
struct CrossPointFirmwareService: DeviceService {
    
    /// mDNS hostname — preferred, resolved via Bonjour.
    static let localHostname = "crosspoint.local"
    /// Static IP fallback when mDNS is unavailable.
    static let defaultIP = "192.168.4.1"
    
    let baseURL: URL
    
    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10
        config.timeoutIntervalForResource = 30
        return URLSession(configuration: config)
    }()
    
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
            return DeviceFile(name: name, isDirectory: isDir)
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
        
        let (_, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw DeviceError.folderCreationFailed
        }
    }
    
    func uploadFile(data: Data, filename: String, toFolder folder: String) async throws {
        // CrossPoint: path is a query parameter, filename is just the name
        var components = URLComponents(url: baseURL.appendingPathComponent("upload"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "path", value: "/\(folder)")]
        
        guard let url = components.url else { throw DeviceError.invalidResponse }
        
        var request = URLRequest(url: url, timeoutInterval: 30)
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
        request.httpBody = body
        
        let (_, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw DeviceError.uploadFailed(statusCode: code)
        }
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
}

// MARK: - Multipart Form Data Helpers

extension Data {
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
