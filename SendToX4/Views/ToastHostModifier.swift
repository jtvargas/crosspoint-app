import SwiftUI

/// Root and modal hosts share one manager-owned lifetime, never competing timers.
struct ToastHostModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var toast: ToastManager?
    var feedback: Bool

    private var entrance: AnyTransition {
        reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity)
    }

    private var animation: Animation {
        reduceMotion ? .easeOut(duration: 0.2) : .spring(duration: 0.4, bounce: 0.2)
    }

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                if let toast, let message = toast.hud {
                    ToastBanner(message: message) {
                        toast.dismissHUD(id: message.id)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .transition(entrance)
                }
            }
            .overlay {
                if let toast, let message = toast.center {
                    ToastBanner(message: message) {
                        toast.dismissCenter(id: message.id)
                    }
                    .padding(.horizontal, 24)
                    .transition(.opacity)
                }
            }
            .animation(animation, value: toast?.hud != nil)
            .animation(.easeOut(duration: 0.2), value: toast?.center != nil)
            // Only the root emits feedback; modal hosts display the same message.
            .sensoryFeedback(trigger: toast?.hud?.id) { _, newValue in
                guard feedback, newValue != nil, let kind = toast?.hud?.kind else { return nil }
                switch kind {
                case .error: return .error
                case .success: return .success
                case .queued: return .selection
                }
            }
    }
}

extension View {
    func toastHost(_ toast: ToastManager?, feedback: Bool = false) -> some View {
        modifier(ToastHostModifier(toast: toast, feedback: feedback))
    }
}
