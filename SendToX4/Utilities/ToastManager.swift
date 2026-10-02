import SwiftUI

/// Independent top and center channels with a fresh lifetime for every request.
/// Root and modal `toastHost` presenters share this state and retain their view
/// identity when a visible message is replaced, including identical messages.
@MainActor
@Observable
final class ToastManager {
    private(set) var hud: ToastMessage?
    private(set) var center: ToastMessage?

    @ObservationIgnored private var hudTask: Task<Void, Never>?
    @ObservationIgnored private var centerTask: Task<Void, Never>?

    deinit {
        hudTask?.cancel()
        centerTask?.cancel()
    }

    func showSuccess(_ title: String, subtitle: String? = nil) {
        presentHUD(ToastMessage(kind: .success, title: title, subtitle: subtitle, duration: 2.5))
    }

    func showQueued(_ title: String, subtitle: String? = nil) {
        presentHUD(ToastMessage(kind: .queued, title: title, subtitle: subtitle, duration: 2.5))
    }

    func showError(_ title: String, subtitle: String? = nil) {
        // The complete diagnostic remains in conversion history / lastError.
        let summary = subtitle?.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        presentHUD(ToastMessage(
            kind: .error,
            title: title,
            subtitle: summary.flatMap { $0.isEmpty ? nil : $0.truncated(to: 120) },
            duration: 4
        ))
    }

    func showCopied(_ title: String? = nil) {
        centerTask?.cancel()
        let message = ToastMessage(kind: .success, title: title ?? loc(.toastCopied), subtitle: nil, duration: 1.5)
        center = message
        centerTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(message.duration))
            } catch {
                // Sleep cancellation means a replacement or explicit dismissal.
                return
            }
            guard !Task.isCancelled else { return }
            self?.dismissCenter(id: message.id)
        }
    }

    func dismissHUD(id: UUID) {
        guard hud?.id == id else { return }
        hudTask?.cancel()
        hudTask = nil
        hud = nil
    }

    func dismissCenter(id: UUID) {
        guard center?.id == id else { return }
        centerTask?.cancel()
        centerTask = nil
        center = nil
    }

    private func presentHUD(_ message: ToastMessage) {
        hudTask?.cancel()
        hud = message
        hudTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(message.duration))
            } catch {
                // A newer request owns the channel and its full reading time.
                return
            }
            guard !Task.isCancelled else { return }
            self?.dismissHUD(id: message.id)
        }
    }
}
