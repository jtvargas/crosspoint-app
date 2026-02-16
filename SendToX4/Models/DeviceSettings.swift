import Foundation
import SwiftData

// MARK: - AppLanguage

/// Supported app languages. Add new cases here to scale to more languages.
enum AppLanguage: String, Codable, CaseIterable {
    /// Use the system locale to determine the language.
    case system = ""
    case en = "en"
    case zhHans = "zh-Hans"

    /// Display name shown in the language picker — each language shows in its own script.
    var displayName: String {
        switch self {
        case .system: return loc(.languageSystemDefault)
        case .en:     return loc(.languageEnglish)
        case .zhHans: return loc(.languageChinese)
        }
    }
}

// MARK: - FirmwareType

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

    /// Localized display name for the settings picker.
    var displayName: String {
        switch self {
        case .stock:      return loc(.firmwareStock)
        case .crossPoint: return loc(.firmwareCrossPoint)
        case .custom:     return loc(.firmwareCustom)
        }
    }
}

/// Persisted device configuration. Only one instance should exist.
@Model
final class DeviceSettings {
    var firmwareTypeRaw: String
    var customIP: String
    var showFileManager: Bool

    // MARK: - Per-Feature Destination Folders

    /// Destination folder for Convert (EPUBs). Default: "content".
    var convertFolder: String

    /// Destination folder for WallpaperX (wallpapers). Default: "sleep".
    var wallpaperFolder: String

    // MARK: - Language

    /// BCP-47 language code, or empty string for system default.
    var languageCode: String
    
    var firmwareType: FirmwareType {
        get { FirmwareType(rawValue: firmwareTypeRaw) ?? .stock }
        set { firmwareTypeRaw = newValue.rawValue }
    }

    /// Typed accessor for the language preference.
    var appLanguage: AppLanguage {
        get { AppLanguage(rawValue: languageCode) ?? .system }
        set { languageCode = newValue.rawValue }
    }
    
    /// The resolved host address based on firmware type and custom setting.
    var resolvedHost: String {
        switch firmwareType {
        case .custom: return customIP.isEmpty ? FirmwareType.stock.defaultHost : customIP
        default: return firmwareType.defaultHost
        }
    }
    
    init(
        firmwareType: FirmwareType = .stock,
        customIP: String = "",
        convertFolder: String = "content",
        wallpaperFolder: String = "sleep",
        showFileManager: Bool = false,
        languageCode: String = ""
    ) {
        self.firmwareTypeRaw = firmwareType.rawValue
        self.customIP = customIP
        self.convertFolder = convertFolder
        self.wallpaperFolder = wallpaperFolder
        self.showFileManager = showFileManager
        self.languageCode = languageCode
    }
}
