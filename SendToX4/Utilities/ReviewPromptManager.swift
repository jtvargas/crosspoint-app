import Foundation

/// Tracks in-app review prompt eligibility using UserDefaults.
///
/// Rules:
/// - Maximum **2 prompts per app version** (tracked by `MARKETING_VERSION`).
/// - **1st prompt**: After the user's first successful file transfer.
/// - **2nd prompt**: Only after at least 5 days since first launch and another successful transfer.
///
/// Call `recordSuccessAndShouldPrompt()` after each positive action. If it returns `true`,
/// the caller should trigger `requestReview()` and then call `recordPromptShown()`.
nonisolated struct ReviewPromptManager {

    // MARK: - UserDefaults Keys

    private static let firstLaunchDateKey = "reviewFirstLaunchDate"
    private static let lastPromptDateKey = "reviewLastPromptDate"

    /// Returns the key used to store the prompt count for a given version.
    private static func promptCountKey(for version: String) -> String {
        "reviewPromptCount_\(version)"
    }

    // MARK: - Constants

    /// Minimum days since first launch before the 2nd prompt is allowed.
    private static let minimumDaysForSecondPrompt: TimeInterval = 5 * 24 * 60 * 60

    /// Maximum number of review prompts per app version.
    private static let maxPromptsPerVersion = 2

    // MARK: - Public API

    /// Record the first launch date if not already set. Call once at app startup.
    static func registerFirstLaunchIfNeeded() {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: firstLaunchDateKey) == nil {
            defaults.set(Date().timeIntervalSince1970, forKey: firstLaunchDateKey)
        }
    }

    /// Evaluate whether a review prompt should be shown after a successful action.
    ///
    /// - Returns: `true` if the prompt should be shown; `false` otherwise.
    static func shouldPromptAfterSuccess() -> Bool {
        let defaults = UserDefaults.standard
        let version = currentAppVersion

        let promptCount = defaults.integer(forKey: promptCountKey(for: version))

        // Already shown max times for this version
        guard promptCount < maxPromptsPerVersion else { return false }

        if promptCount == 0 {
            // 1st prompt: allowed on any successful action
            return true
        }

        // 2nd prompt: requires >= 5 days since first launch
        guard let firstLaunchInterval = defaults.object(forKey: firstLaunchDateKey) as? TimeInterval else {
            return false
        }
        let firstLaunchDate = Date(timeIntervalSince1970: firstLaunchInterval)
        let daysSinceFirstLaunch = Date().timeIntervalSince(firstLaunchDate)

        return daysSinceFirstLaunch >= minimumDaysForSecondPrompt
    }

    /// Record that a review prompt was just shown. Call after `requestReview()`.
    static func recordPromptShown() {
        let defaults = UserDefaults.standard
        let version = currentAppVersion
        let key = promptCountKey(for: version)

        let current = defaults.integer(forKey: key)
        defaults.set(current + 1, forKey: key)
        defaults.set(Date().timeIntervalSince1970, forKey: lastPromptDateKey)
    }

    // MARK: - Private

    private static var currentAppVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
    }
}
