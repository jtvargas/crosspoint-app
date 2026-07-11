import SwiftUI
import WebKit

/// WKWebView wrapper that renders an `EPUBDocument` through
/// `EPUBSchemeHandler` (lazy zip streaming) and reports scroll progress.
struct ReaderWebView {
    let document: EPUBDocument
    let fontScale: Double
    /// Set to a chapter anchor ("chapter-2") to scroll there; cleared after.
    @Binding var chapterAnchor: String?
    /// Progress to restore once the document finishes loading.
    let initialProgress: Double
    /// Debounced scroll-progress callback (0...1).
    let onProgress: (Double) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onProgress: onProgress, initialProgress: initialProgress)
    }

    private func makeWebView(coordinator: Coordinator) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.setURLSchemeHandler(
            EPUBSchemeHandler(document: document),
            forURLScheme: EPUBSchemeHandler.scheme
        )
        configuration.userContentController.add(coordinator, name: "reader")

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = coordinator
        webView.isOpaque = false
        #if os(iOS)
        webView.scrollView.contentInsetAdjustmentBehavior = .always
        webView.backgroundColor = .systemBackground
        #endif
        webView.load(URLRequest(url: EPUBSchemeHandler.readerURL))
        coordinator.webView = webView
        coordinator.pendingFontScale = fontScale
        return webView
    }

    private func update(_ webView: WKWebView, coordinator: Coordinator) {
        if coordinator.appliedFontScale != fontScale {
            coordinator.applyFontScale(fontScale)
        }
        if let anchor = chapterAnchor {
            coordinator.jump(to: anchor)
            // Clear the trigger outside the update pass
            DispatchQueue.main.async { chapterAnchor = nil }
        }
    }

    // MARK: - Coordinator

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        weak var webView: WKWebView?
        var appliedFontScale: Double = 1.0
        var pendingFontScale: Double = 1.0
        private var isLoaded = false
        private let onProgress: (Double) -> Void
        private let initialProgress: Double
        private var lastReported: Double = -1

        init(onProgress: @escaping (Double) -> Void, initialProgress: Double) {
            self.onProgress = onProgress
            self.initialProgress = initialProgress
        }

        func applyFontScale(_ scale: Double) {
            appliedFontScale = scale
            guard isLoaded else {
                pendingFontScale = scale
                return
            }
            webView?.evaluateJavaScript("window.crossxSetFontScale(\(scale))")
        }

        func jump(to anchor: String) {
            guard isLoaded else { return }
            webView?.evaluateJavaScript("window.crossxJumpToAnchor('\(anchor)')")
        }

        nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            MainActor.assumeIsolated {
                isLoaded = true
                if pendingFontScale != 1.0 {
                    appliedFontScale = pendingFontScale
                    webView.evaluateJavaScript("window.crossxSetFontScale(\(pendingFontScale))")
                }
                if initialProgress > 0.01 {
                    webView.evaluateJavaScript("window.crossxRestoreProgress(\(initialProgress))")
                }
            }
        }

        nonisolated func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            MainActor.assumeIsolated {
                guard message.name == "reader",
                      let body = message.body as? [String: Any],
                      let progress = body["progress"] as? Double else {
                    return
                }
                // Debounce tiny movements
                if abs(progress - lastReported) >= 0.005 {
                    lastReported = progress
                    onProgress(progress)
                }
            }
        }
    }
}

#if os(iOS)
extension ReaderWebView: UIViewRepresentable {
    func makeUIView(context: Context) -> WKWebView {
        makeWebView(coordinator: context.coordinator)
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        update(uiView, coordinator: context.coordinator)
    }

    static func dismantleUIView(_ uiView: WKWebView, coordinator: Coordinator) {
        // Break the WKUserContentController -> handler retain cycle
        uiView.configuration.userContentController.removeScriptMessageHandler(forName: "reader")
        uiView.stopLoading()
        uiView.navigationDelegate = nil
    }
}
#elseif os(macOS)
extension ReaderWebView: NSViewRepresentable {
    func makeNSView(context: Context) -> WKWebView {
        makeWebView(coordinator: context.coordinator)
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        update(nsView, coordinator: context.coordinator)
    }

    static func dismantleNSView(_ nsView: WKWebView, coordinator: Coordinator) {
        // Break the WKUserContentController -> handler retain cycle
        nsView.configuration.userContentController.removeScriptMessageHandler(forName: "reader")
        nsView.stopLoading()
        nsView.navigationDelegate = nil
    }
}
#endif
