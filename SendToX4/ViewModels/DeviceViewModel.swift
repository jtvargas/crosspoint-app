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

    // MARK: - Internal State

    private(set) var activeService: (any DeviceService)?
    private var discoveryResult: DiscoveryResult = .notFound

    // MARK: - Actions

    /// Search for the X4 device using auto-detection or configured settings.
    func search(settings: DeviceSettings?) async {
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

        if !isConnected {
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
        activeService = nil
        isConnected = false
        firmwareLabel = loc(.notConnected)
        connectedHost = nil
        errorMessage = nil
        uploadProgress = 0
    }

    /// Upload a file to the device with progress reporting.
    /// Sets global `isUploading` / `uploadFilename` so any tab can show progress.
    func upload(data: Data, filename: String, toFolder folder: String) async throws {
        guard let service = activeService else {
            throw DeviceError.unreachable
        }

        isUploading = true
        uploadFilename = filename
        uploadProgress = 0

        defer {
            isUploading = false
            uploadFilename = nil
        }

        try await service.ensureFolder(folder)
        try await service.uploadFile(data: data, filename: filename, toFolder: folder) { [weak self] progress in
            Task { @MainActor [weak self] in
                self?.uploadProgress = progress
            }
        }

        uploadProgress = 1.0
    }
}
