import Foundation
import SwiftData

/// Manages X4 device connectivity state and auto-detection.
@MainActor
@Observable
final class DeviceViewModel {

    // MARK: - Published State

    var isConnected = false
    var isSearching = false
    var firmwareLabel = "Not Connected"
    var errorMessage: String?

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
        isSearching = false

        if !isConnected {
            errorMessage = "X4 not found. Connect to the X4 WiFi hotspot and try again."
        }
    }

    /// Refresh the connection status.
    func refresh(settings: DeviceSettings?) async {
        await search(settings: settings)
    }

    /// Upload an EPUB file to the device.
    func upload(data: Data, filename: String, toFolder folder: String) async throws {
        guard let service = activeService else {
            throw DeviceError.unreachable
        }
        try await service.ensureFolder(folder)
        try await service.uploadFile(data: data, filename: filename, toFolder: folder)
    }
}
