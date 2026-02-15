import SwiftUI

/// Centralized color palette for the app.
///
/// Three core colors plus one utility color:
/// - **accent** (teal): primary brand, interactive elements, activity icons
/// - **success** (green): sent, connected, strong signal
/// - **error** (red): failures, destructive states, weak signal
/// - **warning** (orange): searching, moderate signal (used sparingly)
///
/// System semantic colors (`.secondary`, `.tertiary`) are used directly
/// for text hierarchy and don't need wrapping here.
enum AppColor {

    // MARK: - Core Palette

    /// Primary brand / accent — teal.
    /// Used for interactive elements, file/folder icons, activity event icons.
    static let accent = Color.teal

    /// Success state — green.
    /// Used for "sent", "connected", strong WiFi signal.
    static let success = Color.green

    /// Error / destructive state — red.
    /// Used for failures, validation errors, weak signal, destructive actions.
    static let error = Color.red

    // MARK: - Utility

    /// Warning / in-progress state — orange.
    /// Used sparingly for "searching" and moderate WiFi signal.
    static let warning = Color.orange
}
