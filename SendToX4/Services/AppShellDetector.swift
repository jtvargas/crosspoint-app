import Foundation
import SwiftSoup

/// A hint to skip pre-fetched Readability, never a reason to skip static extraction.
nonisolated enum AppShellDetector {
    static func isAppShell(_ html: String) -> Bool {
        guard let document = try? SwiftSoup.parse(html),
              let body = document.body() else { return false }
        let hasAppCode = (try? document.select("script[src], script[type=module]").isEmpty()) == false
        let hasMountPoint = (try? body.select("#root, #app, #__next, #__nuxt").isEmpty()) == false
        guard hasAppCode || hasMountPoint else { return false }

        // Script data, CSS and no-JS notices are not rendered article text.
        _ = try? body.select("script, style, noscript, template, [hidden], [aria-hidden=true]").remove()
        guard let text = try? body.text() else { return false }
        return text.count < 400
    }
}
