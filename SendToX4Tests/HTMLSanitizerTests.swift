import Testing
@testable import SendToX4

struct HTMLSanitizerTests {

    @Test func stripsScriptsStylesAndMedia() throws {
        let html = """
        <div><script>alert(1)</script><style>p{}</style>
        <iframe src="x"></iframe><video src="v.mp4"></video>
        <p>Real content stays.</p></div>
        """
        let result = try HTMLSanitizer.sanitize(html)
        #expect(result.contains("Real content stays."))
        #expect(!result.contains("script"))
        #expect(!result.contains("alert"))
        #expect(!result.contains("iframe"))
        #expect(!result.contains("video"))
    }

    @Test func stripsImagesByDefault() throws {
        let html = """
        <div><p>Text before.</p>
        <img src="a.png" alt="x"/><picture><img src="b.png"/></picture>
        <figure><img src="c.png"/><figcaption>Cap</figcaption></figure>
        <p>Text after.</p></div>
        """
        let result = try HTMLSanitizer.sanitize(html)
        #expect(!result.contains("<img"))
        #expect(!result.contains("<picture"))
        #expect(!result.contains("<figure"))
        #expect(result.contains("Text before."))
        #expect(result.contains("Text after."))
    }

    @Test func removesShareWidgets() throws {
        let html = """
        <div><p>Article text.</p>
        <div class="share-buttons"><a href="#">Tweet</a></div>
        <div class="social-links">Follow us</div></div>
        """
        let result = try HTMLSanitizer.sanitize(html)
        #expect(!result.contains("Tweet"))
        #expect(!result.contains("Follow us"))
        #expect(result.contains("Article text."))
    }

    @Test func keepsContentDespiteClutterClassName() throws {
        // An element whose class merely CONTAINS "share" but that holds real
        // article content (many paragraphs) must NOT be removed.
        let paragraphs = (1...5).map { "<p>Paragraph number \($0) with some real article words in it.</p>" }
            .joined()
        let html = "<div class=\"share-story-content\">\(paragraphs)</div>"
        let result = try HTMLSanitizer.sanitize(html)
        #expect(result.contains("Paragraph number 3"))
    }

    @Test func stripsAttributesButUnwrapsLinks() throws {
        let html = """
        <div><p style="color:red" class="big" onclick="evil()">Styled</p>
        <a href="https://example.com">Linked text</a></div>
        """
        let result = try HTMLSanitizer.sanitize(html)
        #expect(!result.contains("style="))
        #expect(!result.contains("class="))
        #expect(!result.contains("onclick"))
        // Links are unwrapped to plain text
        #expect(!result.contains("<a "))
        #expect(result.contains("Linked text"))
    }

    @Test func sanitizeToXHTMLProducesClosedTags() throws {
        let html = "<div><p>One<br>Two</p></div>"
        let result = try HTMLSanitizer.sanitizeToXHTML(html)
        // XML syntax self-closes void elements
        #expect(result.contains("<br />") || result.contains("<br/>"))
        #expect(result.contains("One"))
        #expect(result.contains("Two"))
    }
}
