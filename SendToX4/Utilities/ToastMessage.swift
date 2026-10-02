import Foundation

/// A fresh identity restarts presentation even when the message text is unchanged.
struct ToastMessage: Equatable, Identifiable {
    enum Kind {
        case success
        case queued
        case error
    }

    let id = UUID()
    let kind: Kind
    let title: String
    let subtitle: String?
    let duration: Double
}
