#if canImport(UIKit)
import UIKit

/// Presents from a window-attached SwiftUI background without adding a second sheet.
final class EPUBSharePresenter: UIViewController, UIPopoverPresentationControllerDelegate {
    private let activityController: ActivityController
    private var onDismiss: (() -> Void)?
    private var didPresentActivity = false

    final class ActivityController: UIActivityViewController {
        var usesSheetFallback = true

        // UIActivityViewController ignores attempts to set .pageSheet on iOS 26.
        override var modalPresentationStyle: UIModalPresentationStyle {
            get { usesSheetFallback ? .pageSheet : super.modalPresentationStyle }
            set { super.modalPresentationStyle = newValue }
        }
    }

    init(activityItems: [Any], onDismiss: @escaping () -> Void) {
        activityController = ActivityController(
            activityItems: activityItems,
            applicationActivities: nil
        )
        self.onDismiss = onDismiss
        super.init(nibName: nil, bundle: nil)
        activityController.completionWithItemsHandler = { [weak self] _, _, _, _ in
            Task { @MainActor in
                self?.finish()
            }
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !didPresentActivity, view.window != nil else { return }
        didPresentActivity = true

        Self.configurePresentation(activityController, sourceView: view)
        activityController.presentationController?.delegate = self
        present(activityController, animated: true)
    }

    static func configurePresentation(
        _ activityController: ActivityController,
        sourceView: UIView?
    ) {
        // Never use an unattached view or another scene's key window as an anchor.
        guard let sourceView, let window = sourceView.window,
              window.windowScene?.activationState == .foregroundActive else {
            activityController.usesSheetFallback = true
            return
        }

        // Set an anchor even on iPhone: UIKit may adapt to a popover in multitasking.
        activityController.usesSheetFallback = false
        activityController.modalPresentationStyle = .popover
        if let popover = activityController.popoverPresentationController {
            popover.sourceView = sourceView
            popover.sourceRect = CGRect(
                x: sourceView.bounds.midX, y: sourceView.bounds.midY, width: 1, height: 1
            )
            popover.permittedArrowDirections = []
        }
    }

    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        finish()
    }

    private func finish() {
        let dismiss = onDismiss
        onDismiss = nil
        dismiss?()
    }
}
#endif
