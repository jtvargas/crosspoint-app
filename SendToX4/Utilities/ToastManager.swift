import AlertToast
import SwiftUI

/// Centralized toast notification manager for the app.
///
/// Provides two independent toast channels:
/// - **HUD** (`.hud`): drops from the top for action confirmations (sent, queued, errors)
/// - **Center** (`.alert`): centered popup for quick actions (copy, etc.)
///
/// Usage: call convenience methods from ViewModels (passed as parameter)
/// or directly from Views. The `.toast()` modifiers are attached once
/// at the root view level (`MainView`).
@MainActor
@Observable
final class ToastManager {

    // MARK: - HUD Channel (top drop-down)

    var showHUD = false
    var hudToast = AlertToast(displayMode: .hud, type: .regular, title: "")

    // MARK: - Center Channel (center popup)

    var showCenter = false
    var centerToast = AlertToast(displayMode: .alert, type: .regular, title: "")

    // MARK: - Convenience: Success (.hud + checkmark)

    /// Show a success HUD toast (green checkmark, drops from top).
    func showSuccess(_ title: String, subtitle: String? = nil) {
        hudToast = AlertToast(
            displayMode: .hud,
            type: .complete(AppColor.success),
            title: title,
            subTitle: subtitle
        )
        showHUD = true
    }

    // MARK: - Convenience: Queued (.hud + tray icon)

    /// Show a "queued" HUD toast (orange tray icon, drops from top).
    func showQueued(_ title: String, subtitle: String? = nil) {
        hudToast = AlertToast(
            displayMode: .hud,
            type: .systemImage("tray.and.arrow.down.fill", AppColor.warning),
            title: title,
            subTitle: subtitle
        )
        showHUD = true
    }

    // MARK: - Convenience: Error (.hud + xmark)

    /// Show an error HUD toast (red xmark, drops from top).
    func showError(_ title: String, subtitle: String? = nil) {
        hudToast = AlertToast(
            displayMode: .hud,
            type: .error(AppColor.error),
            title: title,
            subTitle: subtitle
        )
        showHUD = true
    }

    // MARK: - Convenience: Copied (.alert + centered checkmark)

    /// Show a centered "copied" toast (green checkmark, brief popup in center).
    func showCopied(_ title: String? = nil) {
        centerToast = AlertToast(
            displayMode: .alert,
            type: .complete(AppColor.success),
            title: title ?? loc(.toastCopied)
        )
        showCenter = true
    }
}
