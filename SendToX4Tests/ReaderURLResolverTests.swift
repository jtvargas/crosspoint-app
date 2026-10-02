import Foundation
import Testing
@testable import SendToX4

struct ReaderURLResolverTests {
    @Test(arguments: [
        ("/work/reader/article", "/work/article"),
        ("/work/ReAdEr/article/", "/work/article/"),
        ("/reader/", "/"),
        ("/reader/reader/article", "/article"),
        ("/work/%72eader/a%2Fb?next=%2Freader%2Fx#reader", "/work/a%2Fb?next=%2Freader%2Fx#reader")
    ])
    func removesOnlyReaderSegments(paths: (String, String)) throws {
        let input = try #require(URL(string: "https://example.com\(paths.0)"))
        #expect(ReaderURLResolver.isReaderURL(input))
        #expect(ReaderURLResolver.candidates(for: input).map(\.absoluteString) == [
            "https://example.com\(paths.1)", input.absoluteString
        ])
    }

    @Test func resolvesReportedGatesNotesPath() throws {
        let input = try #require(URL(string: "https://www.gatesnotes.com/work/make-ai-work-for-everyone/reader/a-turbulent-ai-era-and-critical-choices-to-make"))
        #expect(ReaderURLResolver.candidates(for: input).map(\.absoluteString) == [
            "https://www.gatesnotes.com/work/make-ai-work-for-everyone/a-turbulent-ai-era-and-critical-choices-to-make",
            input.absoluteString
        ])
    }

    @Test func canonicalLinkPrecedesPathGuess() throws {
        let input = try #require(URL(string: "https://example.com/reader/article"))
        let html = """
        <html><head><LINK href='https://publisher.example/story?a=1&amp;b=2' rel='alternate CANONICAL'></head></html>
        """
        #expect(ReaderURLResolver.candidates(for: input, html: html).map(\.absoluteString) == [
            "https://publisher.example/story?a=1&b=2", "https://example.com/article", input.absoluteString
        ])
    }

    @Test(arguments: ["/relative", "//example.com/story", "javascript:alert(1)", "file:///story", "https:///", "https://example.com/reader/article"])
    func rejectsInvalidOrSelfCanonical(href: String) throws {
        let input = try #require(URL(string: "https://example.com/reader/article"))
        #expect(ReaderURLResolver.candidates(for: input, html: "<link rel='canonical' href='\(href)'>") == ReaderURLResolver.candidates(for: input))
    }

    @Test func deduplicatesCanonicalPathGuess() throws {
        let input = try #require(URL(string: "https://example.com/reader/article"))
        #expect(ReaderURLResolver.candidates(for: input, html: "<link rel='canonical' href='https://example.com/article'>").map(\.absoluteString) == [
            "https://example.com/article", input.absoluteString
        ])
    }

    @Test(arguments: ["/article", "/reader", "/myreader/article", "/article?view=/reader/x", "/article#/reader/x", "/a%2Freader%2Fb"])
    func leavesNonReaderURLsUntouched(path: String) throws {
        let input = try #require(URL(string: "https://example.com\(path)"))
        #expect(ReaderURLResolver.isReaderURL(input) == false)
        #expect(ReaderURLResolver.candidates(for: input, html: "<link rel='canonical' href='https://other.example/story'>") == [input])
    }

    @Test func distinguishesEmptyShellFromShortArticle() {
        #expect(ReaderURLResolver.hasNoContent("<html><body><div id='__next'></div><script>hydrate()</script><noscript>Enable JavaScript</noscript></body></html>"))
        #expect(ReaderURLResolver.hasNoContent("<html><body><article><p>A short article.</p></article><script>hydrate()</script></body></html>") == false)
    }
}
