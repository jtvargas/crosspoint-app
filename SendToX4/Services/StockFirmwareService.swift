import Foundation

/// Device service implementation for the Stock firmware (ESP32-based HTTP server).
/// Default IP: 192.168.3.3
struct StockFirmwareService: DeviceService {
    let baseURL: URL
    
    /// URLSession with short timeouts for device communication.
    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10
        config.timeoutIntervalForResource = 30
        return URLSession(configuration: config)
    }()
    
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
            return DeviceFile(name: name, isDirectory: type == "dir")
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
    
    func uploadFile(data: Data, filename: String, toFolder folder: String) async throws {
        let url = baseURL.appendingPathComponent("edit")
        var request = URLRequest(url: url)
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
        request.httpBody = body
        
        let (_, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw DeviceError.uploadFailed(statusCode: code)
        }
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
}
