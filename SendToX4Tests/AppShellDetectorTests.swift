import Foundation
import Testing
@testable import SendToX4

struct AppShellDetectorTests {
    @Test(arguments: [
        "<html><head><script type='module' crossorigin src='/assets/index.js'></script></head><body><div id='root'></div></body></html>",
        "<div id='app'>Loading…</div>",
        "<div id='__next'></div><script src='/bundle.js'></script>",
        "<script type='module'>startApp()</script><p>Please wait</p>"
    ])
    func detectsEmptyApplicationShell(html: String) {
        #expect(AppShellDetector.isAppShell(html))
    }

    @Test(arguments: ["", "<p>A short, plain article.</p>", "<html><head><title>Empty</title></head></html>"])
    func doesNotClassifyPlainShortPages(html: String) {
        #expect(!AppShellDetector.isAppShell(html))
    }

    @Test(arguments: [399, 400, 401])
    func usesVisibleContentBoundary(length: Int) {
        let html = "<script src='/bundle.js'></script><div id='root'><p>\(String(repeating: "x", count: length))</p></div>"
        #expect(AppShellDetector.isAppShell(html) == (length < 400))
    }

    @Test func ignoresNonArticlePayloads() {
        let payload = String(repeating: "not article text ", count: 100)
        let html = """
        <script type='module'>\(payload)</script><div id='root'></div>
        <style>\(payload)</style><noscript>\(payload)</noscript>
        <template>\(payload)</template><div hidden>\(payload)</div>
        """
        #expect(AppShellDetector.isAppShell(html))
    }
}
