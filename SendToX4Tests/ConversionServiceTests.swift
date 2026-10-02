import Foundation
import Testing
@testable import SendToX4

@MainActor
struct ConversionServiceTests {

    private static func fixturePage(url: URL) -> FetchedPage {
        let paragraphs = (1...12).map {
            "<p>Service paragraph \($0) providing enough content for the extractor threshold to be comfortably exceeded.</p>"
        }.joined()
        let html = """
        <html lang="en"><head>
          <title>Service Fixture | Site</title>
          <meta property="og:title" content="Service Fixture"/>
          <meta name="author" content="Test Author"/>
        </head><body><article>\(paragraphs)</article></body></html>
        """
        return FetchedPage(html: html, finalURL: url, language: "en")
    }

    @Test func convertProducesEPUBAndFilename() async throws {
        let url = URL(string: "https://example.com/post")!
        var service = ConversionService()
        service.fetch = { requested in
            #expect(requested == url)
            return Self.fixturePage(url: requested)
        }
        service.readabilityExtract = { _, _, _, _ in
            Issue.record("Static article must not start WebKit")
            return nil
        }
        service.renderedExtract = { _, _, _ in
            Issue.record("Static article must not navigate live")
            return nil
        }

        let result = try await service.convert(url: url)

        #expect(result.content.title == "Service Fixture")
        #expect(result.filename.hasSuffix(".epub"))
        #expect(result.filename.contains("Service Fixture"))
        #expect(result.finalURL == url)
        // EPUB data starts with the ZIP magic "PK"
        #expect(result.epubData.prefix(2) == Data([0x50, 0x4B]))
    }

    @Test func phasesFireInPipelineOrder() async throws {
        let url = URL(string: "https://example.com/post")!
        var service = ConversionService()
        service.fetch = { Self.fixturePage(url: $0) }

        var phases: [ConversionStatus] = []
        _ = try await service.convert(url: url) { phases.append($0) }

        #expect(phases == [.fetching, .extracting, .building])
    }

    @Test func fetchErrorPropagates() async {
        let url = URL(string: "https://example.com/down")!
        var service = ConversionService()
        service.fetch = { _ in throw FetchError.httpError(statusCode: 503) }

        var thrown = false
        do {
            _ = try await service.convert(url: url)
        } catch {
            thrown = true
        }
        #expect(thrown)
    }

    @Test func twitterFailureFallsThroughToGenericExtraction() async throws {
        // A tweet URL whose fxtwitter call fails must fall through to
        // SwiftSoup extraction of the fetched HTML instead of aborting.
        let url = URL(string: "https://x.com/someone/status/12345")!
        var service = ConversionService()
        service.fetch = { Self.fixturePage(url: $0) }
        service.twitterExtract = { _ in throw FetchError.invalidResponse }

        let result = try await service.convert(url: url)
        #expect(result.content.title == "Service Fixture")
    }

    @Test func unextractablePageThrowsContentTooShort() async {
        let url = URL(string: "https://example.com/empty")!
        var service = ConversionService()
        service.fetch = { url in
            FetchedPage(
                html: "<html><body><p>tiny</p></body></html>",
                finalURL: url,
                language: "en"
            )
        }
        service.readabilityExtract = { _, _, _, _ in nil }
        service.renderedExtract = { _, _, _ in nil }

        var thrownError: Error?
        do {
            _ = try await service.convert(url: url)
        } catch {
            thrownError = error
        }
        // Readability fallback also fails (no meaningful content), so the
        // pipeline surfaces contentTooShort.
        #expect(thrownError is EPUBError)
    }

    @Test func appShellSkipsPrefetchedReadability() async throws {
        var service = ConversionService()
        let url = URL(string: "https://example.com/spa")!
        service.fetch = {
            FetchedPage(html: "<script type='module' src='/app.js'></script><div id='root'></div>",
                        finalURL: $0, language: "en")
        }
        service.readabilityExtract = { _, _, _, _ in
            Issue.record("An empty app shell should go directly to live rendering")
            return nil
        }
        service.renderedExtract = { _, _, _ in Self.renderedArticle }
        let result = try await service.convert(url: url)
        #expect(result.content.title == "Rendered article")
        #expect(result.epubData.prefix(2) == Data([0x50, 0x4B]))
    }

    @Test(arguments: [true, false])
    func ordinaryPageTriesPrefetchedBeforeLive(prefetchedSucceeds: Bool) async throws {
        var service = ConversionService()
        service.fetch = {
            FetchedPage(html: "<p>short static content</p>", finalURL: $0, language: "en")
        }
        var stages: [String] = []
        service.readabilityExtract = { _, _, _, _ in
            stages.append("prefetched")
            return prefetchedSucceeds ? Self.renderedArticle : nil
        }
        service.renderedExtract = { _, _, _ in
            stages.append("live")
            return Self.renderedArticle
        }
        let result = try await service.convert(url: URL(string: "https://example.com/article")!)
        #expect(stages == (prefetchedSucceeds ? ["prefetched"] : ["prefetched", "live"]))
        #expect(result.content.title == "Rendered article")
    }

    @Test func cancellationDoesNotStartLiveNavigation() async {
        var service = ConversionService()
        service.fetch = {
            FetchedPage(html: "<p>short</p>", finalURL: $0, language: "en")
        }
        service.readabilityExtract = { _, _, _, _ in throw CancellationError() }
        service.renderedExtract = { _, _, _ in
            Issue.record("Cancellation must not start another fallback")
            return nil
        }
        await #expect(throws: CancellationError.self) {
            try await service.convert(url: URL(string: "https://example.com/article")!)
        }
    }

    private static var renderedArticle: ExtractedContent {
        ExtractedContent(title: "Rendered article", author: nil, description: "", language: "en",
                         bodyHTML: "<p>\(String(repeating: "Article text. ", count: 50))</p>")
    }
}
