#if canImport(UIKit)
import Testing
import UIKit
@testable import SendToX4

@MainActor
struct EPUBSharePresenterTests {
    @Test(arguments: [false, true])
    func missingOrDetachedAnchorFallsBackToSheet(detached: Bool) {
        let activity = EPUBSharePresenter.ActivityController(
            activityItems: ["EPUB"], applicationActivities: nil
        )
        activity.usesSheetFallback = false
        let sourceView = detached ? UIView() : nil

        EPUBSharePresenter.configurePresentation(activity, sourceView: sourceView)

        #expect(activity.modalPresentationStyle == .pageSheet)
    }

    @Test func detachedPresenterDoesNotStartPresentation() {
        let presenter = EPUBSharePresenter(activityItems: ["EPUB"], onDismiss: {})
        presenter.loadViewIfNeeded()

        presenter.beginAppearanceTransition(true, animated: false)
        presenter.endAppearanceTransition()

        #expect(presenter.presentedViewController == nil)
    }
}
#endif
