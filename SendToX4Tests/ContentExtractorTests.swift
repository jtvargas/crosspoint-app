import Foundation
import Testing
@testable import SendToX4

struct ContentExtractorTests {

    /// A realistic article fixture with metadata and enough body text.
    private static func articleHTML(bodyParagraphs: Int = 10) -> String {
        let paragraphs = (1...bodyParagraphs).map {
            "<p>Paragraph \($0): the quick brown fox jumps over the lazy dog and keeps going for a while longer to add length.</p>"
        }.joined(separator: "\n")
        return """
        <!DOCTYPE html>
        <html lang="en-US">
        <head>
          <title>Fixture Title | Some Site</title>
          <meta property="og:title" content="OG Fixture Title"/>
          <meta name="author" content="Jane Writer"/>
          <meta property="og:description" content="A fixture description."/>
        </head>
        <body>
          <nav><a href="/">Home</a></nav>
          <article>\(paragraphs)</article>
          <footer>Copyright</footer>
        </body>
        </html>
        """
    }

    @Test func extractsMetadataAndBody() throws {
        let url = URL(string: "https://example.com/story")!
        let content = try #require(try ContentExtractor.extract(from: Self.articleHTML(), url: url))
        #expect(content.title == "OG Fixture Title")
        #expect(content.author == "Jane Writer")
        #expect(content.description == "A fixture description.")
        #expect(content.language == "en")
        #expect(content.bodyHTML.contains("Paragraph 5"))
        // Sanitization ran: nav/footer content is gone
        #expect(!content.bodyHTML.contains("Copyright"))
    }

    @Test func shortPageReturnsNilToTriggerFallback() throws {
        let html = """
        <html><head><title>Tiny</title></head>
        <body><article><p>Too short.</p></article></body></html>
        """
        let url = URL(string: "https://example.com/tiny")!
        let content = try ContentExtractor.extract(from: html, url: url)
        #expect(content == nil)
    }

    @Test func fallsBackToTextDensityScoringWithoutArticleTag() throws {
        let paragraphs = (1...10).map {
            "<p>Density paragraph \($0) with plenty of text to accumulate a meaningful score for the extraction heuristics.</p>"
        }.joined()
        let html = """
        <html><head><title>No Container | Site</title></head>
        <body>
          <div class="wrapper"><div class="main-text">\(paragraphs)</div></div>
        </body></html>
        """
        let url = URL(string: "https://example.com/plain")!
        let content = try #require(try ContentExtractor.extract(from: html, url: url))
        #expect(content.bodyHTML.contains("Density paragraph 7"))
    }

    @Test func titleSiteSuffixIsStripped() throws {
        let html = Self.articleHTML().replacingOccurrences(
            of: "<meta property=\"og:title\" content=\"OG Fixture Title\"/>",
            with: ""
        )
        let url = URL(string: "https://example.com/story")!
        let content = try #require(try ContentExtractor.extract(from: html, url: url))
        #expect(content.title == "Fixture Title")
    }
}
