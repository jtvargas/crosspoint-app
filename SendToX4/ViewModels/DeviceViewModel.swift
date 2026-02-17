import Foundation
import SwiftData

/// Manages X4 device connectivity state and auto-detection.
@MainActor
@Observable
final class DeviceViewModel {

    // MARK: - Published State

    var isConnected = false
    var isSearching = false
    var firmwareLabel = loc(.notConnected)
    var errorMessage: String?
    
    /// The hostname or IP of the currently connected device (e.g. "crosspoint.local", "192.168.4.1").
    var connectedHost: String?
    
    /// Upload progress (0.0 to 1.0). Updated during file uploads.
    var uploadProgress: Double = 0

    /// Whether a file upload is currently in progress (global across all features).
    var isUploading = false

    /// The filename of the file currently being uploaded (for display in progress UI).
    var uploadFilename: String?

    // MARK: - Busy Tracking

    /// Count of active non-upload device operations (list, delete, move, etc.).
    /// Uploads are tracked separately via `isUploading`.
    private var activeOperationCount = 0

    /// Whether any device operation is currently in progress.
    /// The health ping suspends itself while this is `true`.
    var isBusy: Bool { isUploading || activeOperationCount > 0 }

    // MARK: - Internal State

    private(set) var activeService: (any DeviceService)?
    private var discoveryResult: DiscoveryResult = .notFound

    /// Background task that periodically checks device reachability.
    private var pingTask: Task<Void, Never>?

    // MARK: - Actions

    /// Search for the X4 device using auto-detection or configured settings.
    func search(settings: DeviceSettings?) async {
        stopHealthPing()
        isSearching = true
        errorMessage = nil

        let result: DiscoveryResult
        if let settings, settings.firmwareType != .stock || !settings.customIP.isEmpty {
            result = await DeviceDiscovery.detect(
                firmwareType: settings.firmwareType,
                customIP: settings.customIP
            )
        } else {
            result = await DeviceDiscovery.detect()
        }

        discoveryResult = result
        activeService = result.service
        isConnected = result.service != nil
        firmwareLabel = result.firmwareLabel
        connectedHost = result.service?.baseURL.host
        isSearching = false

        if isConnected {
            startHealthPing()
        } else {
            errorMessage = loc(.x4NotFoundMessage)
        }
    }

    /// Refresh the connection status.
    func refresh(settings: DeviceSettings?) async {
        await search(settings: settings)
    }

    /// Disconnect from the device and reset connection state.
    /// Blocked while a file upload is in progress to prevent data corruption.
    func disconnect() {
        guard !isUploading else { return }
        stopHealthPing()
        activeService = nil
        isConnected = false
        firmwareLabel = loc(.notConnected)
        connectedHost = nil
        errorMessage = nil
        uploadProgress = 0
    }

    // MARK: - Operation Tracking

    /// Mark the start of a device operation (list, delete, move, etc.).
    /// The health ping suspends while any operations are active.
    func beginOperation() {
        activeOperationCount += 1
    }

    /// Mark the end of a device operation.
    func endOperation() {
        activeOperationCount = max(0, activeOperationCount - 1)
    }

    // MARK: - Health Ping

    /// How often to ping the device for reachability (in seconds).
    private static let pingInterval: Duration = .seconds(12)

    /// Start a background health-ping loop that periodically verifies the device
    /// is still reachable. The ping is skipped whenever the device is busy with
    /// an active operation (upload, file listing, delete, etc.) to avoid saturating
    /// the ESP32's limited resources.
    ///
    /// On ping failure the device is automatically marked as disconnected.
    private func startHealthPing() {
        stopHealthPing()
        pingTask = Task { [weak self] in
            while !Task.isCancelled {
                // Sleep first — the device was just verified during search()
                try? await Task.sleep(for: DeviceViewModel.pingInterval)
                guard !Task.isCancelled else { break }
                guard let self else { break }

                // Skip this cycle if the device is busy with a real operation
                guard self.isConnected, !self.isBusy else { continue }

                guard let service = self.activeService else { break }

                let reachable = await service.checkReachability()

                guard !Task.isCancelled else { break }

                if !reachable {
                    DebugLogger.log("Health ping failed — device unreachable", level: .warning, category: .device)
                    self.isConnected = false
                    self.activeService = nil
                    self.connectedHost = nil
                    self.firmwareLabel = loc(.notConnected)
                    break // Stop the loop — device is gone
                }
            }
        }
    }

    /// Cancel the background health-ping loop.
    private func stopHealthPing() {
        pingTask?.cancel()
        pingTask = nil
    }

    // MARK: - Folder Management

    /// Ensure a folder path exists on the device.
    /// Used by batch operations to pre-create folders once before sending multiple files.
    func ensureFolder(_ path: String) async throws {
        guard let service = activeService else {
            throw DeviceError.unreachable
        }
        try await service.ensureFolder(path)
    }

    // MARK: - Upload

    /// Upload a file to the device with progress reporting.
    /// Sets global `isUploading` / `uploadFilename` so any tab can show progress.
    ///
    /// The `ensureFolder` call has its own internal retry logic (3 attempts with 0.5s delay).
    /// The upload itself has retry logic in the firmware service (2 retries for connection-lost).
    ///
    /// - Parameter skipEnsureFolder: When `true`, skips the per-upload folder existence check.
    ///   Use this when the caller has already pre-ensured the destination folder for a batch.
    func upload(
        data: Data,
        filename: String,
        toFolder folder: String,
        skipEnsureFolder: Bool = false
    ) async throws {
        guard let service = activeService else {
            DebugLogger.log("Upload aborted: device not connected", level: .error, category: .device)
            throw DeviceError.unreachable
        }

        isUploading = true
        uploadFilename = filename
        uploadProgress = 0

        defer {
            isUploading = false
            uploadFilename = nil
        }

        if !skipEnsureFolder {
            DebugLogger.log("Ensuring folder: /\(folder)/", level: .info, category: .device)
            try await service.ensureFolder(folder)
            DebugLogger.log("Folder ready: /\(folder)/", level: .info, category: .device)
        }

        DebugLogger.log("Uploading \(filename) (\(data.count) bytes) to /\(folder)/", level: .info, category: .device)
        try await service.uploadFile(data: data, filename: filename, toFolder: folder) { [weak self] progress in
            Task { @MainActor [weak self] in
                self?.uploadProgress = progress
            }
        }

        uploadProgress = 1.0
        DebugLogger.log("Upload complete: \(filename) -> /\(folder)/", level: .info, category: .device)
    }
}
