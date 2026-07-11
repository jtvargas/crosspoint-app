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
        let result = try HTMLSanitizer.sanitizeToXHTML(html).bodyHTML
        // XML syntax self-closes void elements
        #expect(result.contains("<br />") || result.contains("<br/>"))
        #expect(result.contains("One"))
        #expect(result.contains("Two"))
    }

    // MARK: - Image Preservation (includeImages)

    @Test func keepImagesResolvesAndRewritesSources() throws {
        let html = """
        <div><p>Intro text.</p>
        <img src="/media/photo.png" alt="A photo"/>
        <figure><img src="https://cdn.example.com/pic2.jpg" alt="Second"/>
        <figcaption>Caption text</figcaption></figure></div>
        """
        let result = try HTMLSanitizer.sanitizeToXHTML(
            html,
            baseURI: "https://example.com/article",
            options: SanitizerOptions(keepImages: true)
        )
        #expect(result.images.count == 2)
        #expect(result.images[0].absoluteURL.absoluteString == "https://example.com/media/photo.png")
        #expect(result.images[0].alt == "A photo")
        #expect(result.images[1].absoluteURL.absoluteString == "https://cdn.example.com/pic2.jpg")
        // src rewritten to EPUB-relative placeholder paths
        #expect(result.bodyHTML.contains("src=\"images/img-0.jpg\""))
        #expect(result.bodyHTML.contains("src=\"images/img-1.jpg\""))
        // figure/figcaption preserved
        #expect(result.bodyHTML.contains("<figure>"))
        #expect(result.bodyHTML.contains("Caption text"))
    }

    @Test func keepImagesUsesSrcsetWhenSrcMissing() throws {
        let html = """
        <div><p>Text.</p>
        <img srcset="/small.jpg 400w, /large.jpg 1200w, /huge.jpg 2400w" alt="responsive"/></div>
        """
        let result = try HTMLSanitizer.sanitizeToXHTML(
            html,
            baseURI: "https://example.com/post",
            options: SanitizerOptions(keepImages: true)
        )
        #expect(result.images.count == 1)
        // Largest candidate <= 1600w wins
        #expect(result.images[0].absoluteURL.absoluteString == "https://example.com/large.jpg")
    }

    @Test func keepImagesDropsDataURIsAndTrackingPixels() throws {
        let html = """
        <div><p>Text.</p>
        <img src="data:image/gif;base64,R0lGOD"/>
        <img src="https://tracker.example.com/p.gif" width="1" height="1"/></div>
        """
        let result = try HTMLSanitizer.sanitizeToXHTML(
            html,
            baseURI: "https://example.com",
            options: SanitizerOptions(keepImages: true)
        )
        #expect(result.images.isEmpty)
        #expect(!result.bodyHTML.contains("<img"))
    }

    @Test func collapsesPictureToInnerImg() throws {
        let html = """
        <div><picture>
        <source srcset="/img.webp" type="image/webp"/>
        <img src="/img.png" alt="pic"/>
        </picture></div>
        """
        let result = try HTMLSanitizer.sanitizeToXHTML(
            html,
            baseURI: "https://example.com",
            options: SanitizerOptions(keepImages: true)
        )
        #expect(result.images.count == 1)
        #expect(!result.bodyHTML.contains("<picture"))
        #expect(result.bodyHTML.contains("src=\"images/img-0.jpg\""))
    }
}
