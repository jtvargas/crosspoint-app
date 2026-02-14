import Foundation
import SwiftData

/// Supported firmware types for the Xtreink X4.
enum FirmwareType: String, Codable, CaseIterable {
    case stock = "Stock"
    case crossPoint = "CrossPoint"
    case custom = "Custom"
    
    var defaultHost: String {
        switch self {
        case .stock: return "192.168.3.3"
        case .crossPoint: return "crosspoint.local"
        case .custom: return ""
        }
    }
}

/// Persisted device configuration. Only one instance should exist.
@Model
final class DeviceSettings {
    var firmwareTypeRaw: String
    var customIP: String
    var targetFolder: String
    var showWallpaperX: Bool
    var showFileManager: Bool
    
    var firmwareType: FirmwareType {
        get { FirmwareType(rawValue: firmwareTypeRaw) ?? .stock }
        set { firmwareTypeRaw = newValue.rawValue }
    }
    
    /// The resolved host address based on firmware type and custom setting.
    var resolvedHost: String {
        switch firmwareType {
        case .custom: return customIP.isEmpty ? FirmwareType.stock.defaultHost : customIP
        default: return firmwareType.defaultHost
        }
    }
    
    init(firmwareType: FirmwareType = .stock, customIP: String = "", targetFolder: String = "content", showWallpaperX: Bool = false, showFileManager: Bool = false) {
        self.firmwareTypeRaw = firmwareType.rawValue
        self.customIP = customIP
        self.targetFolder = targetFolder
        self.showWallpaperX = showWallpaperX
        self.showFileManager = showFileManager
    }
}
