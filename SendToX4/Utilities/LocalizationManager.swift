import SwiftUI

// MARK: - LocalizationManager

/// Centralized localization manager that drives language selection across the app.
///
/// Because the project uses `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, this class
/// is implicitly `@MainActor` — which is intentional since it holds UI-related state.
@Observable
final class LocalizationManager {

    // MARK: Singleton

    static let shared = LocalizationManager()

    // MARK: Properties

    /// The user's language preference. Persisted elsewhere (e.g. `DeviceSettings`).
    var currentLanguage: AppLanguage = .system

    /// The concrete BCP-47 language code resolved from `currentLanguage`.
    var resolvedLanguageCode: String {
        switch currentLanguage {
        case .system:
            let preferred = Locale.preferredLanguages.first ?? "en"
            return preferred.hasPrefix("zh") ? "zh-Hans" : "en"
        case .en:
            return "en"
        case .zhHans:
            return "zh-Hans"
        }
    }

    /// A `Locale` derived from the resolved language code, useful for formatting.
    var locale: Locale {
        Locale(identifier: resolvedLanguageCode)
    }

    // MARK: Init

    private init() {}

    // MARK: Convenience

    /// Returns the localized string for the given key using the current language.
    func localized(_ key: L10n.Key) -> String {
        L10n.string(for: key, language: resolvedLanguageCode)
    }

    /// Returns the localized string for the given key, applying `String(format:)` with arguments.
    func localized(_ key: L10n.Key, _ args: CVarArg...) -> String {
        let format = L10n.string(for: key, language: resolvedLanguageCode)
        return String(format: format, arguments: args)
    }
}

// MARK: - Global Convenience

/// Global shorthand for localized string lookup.
func loc(_ key: L10n.Key) -> String {
    LocalizationManager.shared.localized(key)
}

/// Global shorthand for localized string with format arguments.
func loc(_ key: L10n.Key, _ args: CVarArg...) -> String {
    let format = L10n.string(for: key, language: LocalizationManager.shared.resolvedLanguageCode)
    return String(format: format, arguments: args)
}
